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
    else if kind = "categories" or kind = "streams" then
        parseList(json, kind)
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
                else
                    nm = toS(s.name)
                    if nm = "" then nm = "Channel"
                    items.push({ id: toS(s.stream_id), title: nm, HDPosterUrl: toS(s.stream_icon) })
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
