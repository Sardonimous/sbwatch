sub init()
    m.top.functionName = "run"
end sub

sub run()
    m.top.errorMsg = ""
    body = httpGet(m.top.url)
    if m.top.errorMsg <> "" then return

    json = ParseJson(body)
    if json = invalid then
        m.top.errorMsg = "Server returned invalid data"
        return
    end if

    kind = m.top.kind
    if kind = "auth" then
        parseAuth(json)
    else if kind = "categories" or kind = "streams" or kind = "series" then
        parseList(json, kind)
    else if kind = "vodinfo" then
        parseVodInfo(json)
    else if kind = "seriesinfo" then
        parseSeriesInfo(json)
    else if kind = "epg" then
        parseEpg(json)
    end if
end sub

function httpGet(url as String) as String
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.AddHeader("User-Agent", "Mozilla/5.0 (SBWatch)")
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)
    if Left(url, 5) = "https" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.InitClientCertificates()
    end if

    if not xfer.AsyncGetToString() then
        m.top.errorMsg = "Could not start request"
        return ""
    end if

    msg = wait(60000, port)
    if msg = invalid then
        xfer.AsyncCancel()
        m.top.errorMsg = "Request timed out"
        return ""
    end if
    if type(msg) <> "roUrlEvent" then
        m.top.errorMsg = "Unexpected network event"
        return ""
    end if

    code = msg.GetResponseCode()
    if code <> 200 then
        reason = msg.GetFailureReason()
        if reason = invalid then reason = ""
        m.top.errorMsg = "HTTP " + code.ToStr() + " " + reason
        return ""
    end if
    return msg.GetString()
end function

sub parseAuth(json as Object)
    d = { auth: 0, status: "", exp: "" }
    if type(json) = "roAssociativeArray" and json.user_info <> invalid then
        ui = json.user_info
        d.auth = Int(Val(toS(ui.auth)))
        d.status = toS(ui.status)
        d.exp = toS(ui.exp_date)
    end if
    m.top.data = d
end sub

sub parseList(json as Object, kind as String)
    items = []
    if type(json) = "roArray" then
        for each s in json
            if type(s) = "roAssociativeArray" then
                if kind = "categories" then
                    nm = toS(s.category_name)
                    if nm = "" then nm = "Category"
                    items.push({ id: toS(s.category_id), title: nm })
                else if kind = "series" then
                    nm = toS(s.name)
                    if nm = "" then nm = "Series"
                    items.push({ id: toS(s.series_id), title: nm, HDPosterUrl: toS(s.cover), rating: toS(s.rating), added: Int(Val(toS(s.last_modified))), year: yearOf(s) })
                else
                    nm = toS(s.name)
                    if nm = "" then nm = "Channel"
                    items.push({ id: toS(s.stream_id), title: nm, HDPosterUrl: toS(s.stream_icon), rating: toS(s.rating), added: Int(Val(toS(s.added))), year: yearOf(s) })
                end if
            end if
        end for
    end if
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    m.top.content = root
end sub

sub parseEpg(json as Object)
    listings = []
    if type(json) = "roAssociativeArray" and json.epg_listings <> invalid then
        for each l in json.epg_listings
            if type(l) = "roAssociativeArray" then
                listings.push({
                    title: b64(l.title)
                    desc: b64(l.description)
                    start: Int(Val(toS(l.start_timestamp)))
                    stop: Int(Val(toS(l.stop_timestamp)))
                })
            end if
        end for
    end if
    m.top.data = { listings: listings }
end sub

function infoDur(inf as Object) as Integer
    d = Int(Val(toS(inf.duration_secs)))
    if d > 0 then return d
    s = toS(inf.duration)
    if s <> "" then
        parts = s.Tokenize(":")
        if parts.Count() >= 2 then
            total = 0
            for each p in parts
                total = total * 60 + Int(Val(p))
            end for
            return total
        end if
    end if
    return 0
end function

' get_vod_info -> { name, plot, cast, director, genre, year, rating, dur, ext, image }
sub parseVodInfo(json as Object)
    d = { name: "", plot: "", cast: "", director: "", genre: "", year: "", rating: "", dur: 0, ext: "", image: "", vinfo: "", ainfo: "" }
    if type(json) = "roAssociativeArray" then
        inf = json.info
        if type(inf) = "roAssociativeArray" then
            d.vinfo = codecDesc(inf.video)
            d.ainfo = codecDesc(inf.audio)
            d.plot = firstS(inf, ["plot", "description", "overview"])
            d.cast = firstS(inf, ["cast", "actors"])
            d.director = firstS(inf, ["director"])
            d.genre = firstS(inf, ["genre"])
            d.year = firstS(inf, ["releasedate", "release_date", "releaseDate", "year"])
            d.rating = firstS(inf, ["rating", "rating_imdb"])
            d.image = firstS(inf, ["movie_image", "cover_big", "cover"])
            d.dur = infoDur(inf)
        end if
        md = json.movie_data
        if type(md) = "roAssociativeArray" then
            d.ext = toS(md.container_extension)
            d.name = toS(md.name)
        end if
    end if
    m.top.data = d
end sub

' get_series_info -> { name, cover, plot, ..., seasons: [ { num, name, cover, eps: [ {id,num,title,ext,dur,plot,image} ] } ] }
sub parseSeriesInfo(json as Object)
    d = { name: "", cover: "", plot: "", cast: "", director: "", genre: "", year: "", rating: "", seasons: [] }
    if type(json) <> "roAssociativeArray" then
        m.top.data = d
        return
    end if

    inf = json.info
    if type(inf) = "roAssociativeArray" then
        d.name = toS(inf.name)
        d.cover = firstS(inf, ["cover", "backdrop"])
        d.plot = firstS(inf, ["plot", "description"])
        d.cast = firstS(inf, ["cast"])
        d.director = firstS(inf, ["director"])
        d.genre = firstS(inf, ["genre"])
        d.year = firstS(inf, ["releaseDate", "release_date", "releasedate"])
        d.rating = firstS(inf, ["rating"])
    end if

    smeta = {}
    sm = json.seasons
    if type(sm) = "roArray" then
        for each s in sm
            if type(s) = "roAssociativeArray" then
                sn = toS(s.season_number)
                if sn <> "" then smeta[sn] = firstS(s, ["cover_big", "cover"])
            end if
        end for
    end if

    groups = []
    eps = json.episodes
    if type(eps) = "roAssociativeArray" then
        for each k in eps.Keys()
            groups.push({ num: Int(Val(k)), list: eps[k] })
        end for
    else if type(eps) = "roArray" then
        i = 0
        for each lst in eps
            i = i + 1
            groups.push({ num: i, list: lst })
        end for
    end if
    sortByNum(groups)

    for each g in groups
        if type(g.list) = "roArray" then
            out = []
            for each ep in g.list
                if type(ep) = "roAssociativeArray" then
                    plot = ""
                    image = ""
                    dur = 0
                    vinfo = ""
                    ainfo = ""
                    ei = ep.info
                    if type(ei) = "roAssociativeArray" then
                        vinfo = codecDesc(ei.video)
                        ainfo = codecDesc(ei.audio)
                        plot = firstS(ei, ["plot", "description"])
                        image = firstS(ei, ["movie_image", "cover_big"])
                        dur = infoDur(ei)
                    end if
                    out.push({ id: toS(ep.id), num: Int(Val(toS(ep.episode_num))), title: toS(ep.title), ext: toS(ep.container_extension), dur: dur, plot: plot, image: image, vinfo: vinfo, ainfo: ainfo })
                end if
            end for
            sortByNum(out)
            scover = ""
            if smeta.DoesExist(g.num.ToStr()) then scover = smeta[g.num.ToStr()]
            d.seasons.push({ num: g.num, cover: scover, eps: out })
        end if
    end for
    m.top.data = d
end sub

' "hevc 1920x1080" / "dts 5.1(side)" from the provider's ffprobe data, if it has any
function codecDesc(o as Object) as String
    if type(o) <> "roAssociativeArray" then return ""
    c = firstS(o, ["codec_name", "codec"])
    if c = "" then return ""
    out = c
    w = firstS(o, ["width"])
    h = firstS(o, ["height"])
    if w <> "" and w <> "0" and h <> "" and h <> "0" then out = out + " " + w + "x" + h
    lay = firstS(o, ["channel_layout"])
    if lay <> "" then
        out = out + " " + lay
    else
        chn = firstS(o, ["channels"])
        if chn <> "" and chn <> "0" then out = out + " " + chn + "ch"
    end if
    return out
end function

function yearOf(s as Object) as String
    y = firstS(s, ["year", "releaseDate", "release_date", "releasedate"])
    if Len(y) >= 4 then y = Left(y, 4)
    n = Int(Val(y))
    if n >= 1880 and n <= 2100 then return y
    return ""
end function
