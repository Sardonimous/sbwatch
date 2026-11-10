' ---------- shared helpers (included by main scene and tasks) ----------

function toS(v as Dynamic) as String
    if v = invalid then return ""
    t = type(v)
    if t = "roString" or t = "String" then return v
    if t = "roInt" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v.ToStr()
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return Int(v).ToStr()
    if t = "roBoolean" or t = "Boolean" then
        if v then return "true"
        return "false"
    end if
    return ""
end function

function regRead(key as String) as String
    sec = CreateObject("roRegistrySection", "sbwatch")
    if sec.Exists(key) then return sec.Read(key)
    ' settings saved by early builds (before the rename to SBWatch)
    old = CreateObject("roRegistrySection", "streamvault")
    if old.Exists(key) then return old.Read(key)
    return ""
end function

sub regWrite(key as String, value as String)
    sec = CreateObject("roRegistrySection", "sbwatch")
    sec.Write(key, value)
    sec.Flush()
end sub

function normServer(s as String) as String
    s = s.Trim()
    if s = "" then return ""
    low = LCase(s)
    if Left(low, 7) <> "http://" and Left(low, 8) <> "https://" then
        s = "http://" + s
    end if
    while Right(s, 1) = "/"
        s = Left(s, Len(s) - 1)
    end while
    return s
end function

function urlEnc(s as String) as String
    out = ""
    hexd = "0123456789ABCDEF"
    for i = 1 to Len(s)
        ch = Mid(s, i, 1)
        a = Asc(ch)
        if (a >= 48 and a <= 57) or (a >= 65 and a <= 90) or (a >= 97 and a <= 122) or ch = "-" or ch = "_" or ch = "." or ch = "~" then
            out = out + ch
        else
            ba = CreateObject("roByteArray")
            ba.FromAsciiString(ch)
            for each b in ba
                out = out + "%" + Mid(hexd, Int(b / 16) + 1, 1) + Mid(hexd, (b mod 16) + 1, 1)
            end for
        end if
    end for
    return out
end function

function b64(s as Dynamic) as String
    if s = invalid then return ""
    if type(s) <> "roString" and type(s) <> "String" then return ""
    if s = "" then return ""
    ba = CreateObject("roByteArray")
    ba.FromBase64String(s)
    r = ba.ToAsciiString()
    if r = invalid then return ""
    return r
end function

function nowSecs() as Integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

function fmtTime(secs as Integer) as String
    dt = CreateObject("roDateTime")
    dt.FromSeconds(secs)
    dt.ToLocalTime()
    h = dt.GetHours()
    mins = dt.GetMinutes()
    ap = "AM"
    if h >= 12 then ap = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    mm = Right("0" + mins.ToStr(), 2)
    return h12.ToStr() + ":" + mm + " " + ap
end function

function fmtBps(n as Dynamic) as String
    bps = Val(toS(n))
    if bps <= 0 then return "n/a"
    tenths = Int(bps / 100000)
    return (tenths \ 10).ToStr() + "." + (tenths mod 10).ToStr() + " Mbps"
end function

function fldOf(node as Object, name as String) as Dynamic
    if node.hasField(name) then return node.getField(name)
    return invalid
end function

function dumpAA(aa as Object) as String
    out = ""
    for each k in aa.Keys()
        v = aa[k]
        tv = type(v)
        if tv = "roAssociativeArray" or tv = "roArray" then
            sv = "(" + tv + ")"
        else
            sv = toS(v)
        end if
        if Len(sv) > 70 then sv = Left(sv, 67) + "..."
        out = out + k + "=" + sv + "   "
    end for
    return out
end function

function httpFetch(url as String, timeoutMs as Integer) as Dynamic
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
    if not xfer.AsyncGetToString() then return invalid
    msg = wait(timeoutMs, port)
    if msg = invalid then
        xfer.AsyncCancel()
        return invalid
    end if
    if type(msg) <> "roUrlEvent" then return invalid
    if msg.GetResponseCode() <> 200 then return invalid
    return msg.GetString()
end function

function fmtDayTime(secs as Integer) as String
    dt = CreateObject("roDateTime")
    dt.FromSeconds(secs)
    dt.ToLocalTime()
    nd = CreateObject("roDateTime")
    nd.ToLocalTime()
    t = fmtTime(secs)
    if dt.GetDayOfMonth() = nd.GetDayOfMonth() and dt.GetMonth() = nd.GetMonth() then return t
    return Left(dt.GetWeekday(), 3) + " " + t
end function

function chanName(item as Object) as String
    if item.hasField("cname") then
        n = item.cname
        if n <> invalid then
            if n <> "" then return n
        end if
    end if
    return item.title
end function

sub setLogo(p as Object, url as Dynamic)
    u = ""
    if url <> invalid then u = url
    if u = "" then
        p.visible = false
    else
        p.visible = true
        if p.uri <> u then p.uri = u
    end if
end sub
