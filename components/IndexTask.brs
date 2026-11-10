' Builds a compact on-device name index (one line per channel/title):
'     id <TAB> categoryId <TAB> name
' by walking the provider category by category, so memory stays small.
' kind: "live" | "vod" | "series"  (vod/series are ready for later)

sub init()
    m.top.functionName = "run"
end sub

sub run()
    kind = m.top.kind
    action = "get_live_streams"
    idField = "stream_id"
    iconField = "stream_icon"
    if kind = "vod" then
        action = "get_vod_streams"
    else if kind = "series" then
        action = "get_series"
        idField = "series_id"
        iconField = "cover"
    end if

    base = m.top.server + "/player_api.php?username=" + urlEnc(m.top.user) + "&password=" + urlEnc(m.top.pass) + "&action=" + action + "&category_id="
    tmp = "cachefs:/svidx_" + kind + ".tmp"
    fin = "cachefs:/svidx_" + kind + ".txt"
    fs = CreateObject("roFileSystem")
    if fs.Exists(tmp) then fs.Delete(tmp)

    sep = Chr(9)
    ids = m.top.cats
    total = ids.Count()
    count = 0
    fails = 0

    for i = 0 to total - 1
        cid = ids[i]
        body = httpFetch(base + urlEnc(cid), 45000)
        ok = false
        if body <> invalid then
            json = ParseJson(body)
            if type(json) = "roArray" then
                ok = true
                chunk = ""
                for each s in json
                    if type(s) = "roAssociativeArray" then
                        nm = toS(s.name)
                        sid = toS(s[idField])
                        if nm <> "" and sid <> "" then
                            nm = nm.Replace(sep, " ")
                            nm = nm.Replace(Chr(10), " ")
                            nm = nm.Replace(Chr(13), " ")
                            ic = toS(s[iconField])
                            ic = ic.Replace(sep, "")
                            ic = ic.Replace(Chr(10), "")
                            ic = ic.Replace(Chr(13), "")
                            chunk = chunk + sid + sep + cid + sep + nm + sep + ic + Chr(10)
                            count = count + 1
                        end if
                    end if
                end for
                if chunk <> "" then
                    ba = CreateObject("roByteArray")
                    ba.FromAsciiString(chunk)
                    wrote = false
                    if fs.Exists(tmp) then
                        wrote = ba.AppendFile(tmp)
                    else
                        wrote = ba.WriteFile(tmp)
                    end if
                    if not wrote then
                        m.top.result = { ok: false, count: 0, err: "could not write cache file" }
                        return
                    end if
                end if
            end if
        end if
        if not ok then fails = fails + 1
        m.top.progress = i + 1
    end for

    if count = 0 or fails * 2 > total then
        m.top.result = { ok: false, count: count, err: fails.ToStr() + " of " + total.ToStr() + " categories failed" }
        return
    end if

    if fs.Exists(fin) then fs.Delete(fin)
    if not fs.Rename(tmp, fin) then
        m.top.result = { ok: false, count: count, err: "could not finalize cache file" }
        return
    end if
    m.top.result = { ok: true, count: count, err: "" }
end sub
