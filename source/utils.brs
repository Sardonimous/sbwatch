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

function fmtDur(secs as Integer) as String
    if secs < 0 then secs = 0
    h = secs \ 3600
    mm = (secs mod 3600) \ 60
    ss = secs mod 60
    if h > 0 then return h.ToStr() + ":" + Right("0" + mm.ToStr(), 2) + ":" + Right("0" + ss.ToStr(), 2)
    return mm.ToStr() + ":" + Right("0" + ss.ToStr(), 2)
end function

function two(n as Integer) as String
    return Right("0" + n.ToStr(), 2)
end function

' first non-empty string among several possible keys of an AA
function firstS(aa as Object, keys as Object) as String
    if type(aa) <> "roAssociativeArray" then return ""
    for each k in keys
        v = toS(aa[k])
        if v <> "" then return v
    end for
    return ""
end function

' string value of a content-node field ("" if the field does not exist)
function nodeStr(node as Object, name as String) as String
    if node.hasField(name) then return toS(node.getField(name))
    return ""
end function

' insertion sort of an array of AAs by their "num" key
sub sortByNum(arr as Object)
    for i = 1 to arr.Count() - 1
        cur = arr[i]
        j = i - 1
        moving = true
        while moving
            if j < 0 then
                moving = false
            else if arr[j].num > cur.num then
                arr[j + 1] = arr[j]
                j = j - 1
            else
                moving = false
            end if
        end while
        arr[j + 1] = cur
    end for
end sub

function vodFormat(ext as String) as String
    e = LCase(ext)
    if e = "mkv" then return "mkv"
    if e = "mp4" or e = "m4v" or e = "mov" then return "mp4"
    if e = "ts" then return "ts"
    if e = "m3u8" then return "hls"
    return ""
end function

' ---------------------------------------------------------------------
' Arabic support. Roku's fonts have no Arabic glyphs and its text engine
' neither joins letters nor reorders right-to-left text, so Arabic strings
' are shaped here (Arabic Presentation Forms) and put in visual order, and
' shown with the bundled DejaVu Sans font (fonts/LICENSE-DejaVu.txt).
' ---------------------------------------------------------------------

function hasArabic(t as String) as Boolean
    for i = 1 to Len(t)
        c = Asc(Mid(t, i, 1))
        if c >= 1536 and c <= 1791 then return true
        if c >= 1872 and c <= 1919 then return true
        if c >= 64336 and c <= 65023 then return true
        if c >= 65136 and c <= 65279 then return true
    end for
    return false
end function

' letter -> [isolated, final, initial, medial] presentation-form code points
function arTable() as Object
    if m.arTbl <> invalid then return m.arTbl
    data = "1569,65152,0,0,0;1570,65153,65154,0,0;1571,65155,65156,0,0;1572,65157,65158,0,0;1573,65159,65160,0,0;1574,65161,65162,65163,65164;1575,65165,65166,0,0;1576,65167,65168,65169,65170;1577,65171,65172,0,0;1578,65173,65174,65175,65176;1579,65177,65178,65179,65180;1580,65181,65182,65183,65184;1581,65185,65186,65187,65188;1582,65189,65190,65191,65192;1583,65193,65194,0,0;1584,65195,65196,0,0;1585,65197,65198,0,0;1586,65199,65200,0,0;1587,65201,65202,65203,65204;1588,65205,65206,65207,65208;1589,65209,65210,65211,65212;1590,65213,65214,65215,65216;1591,65217,65218,65219,65220;1592,65221,65222,65223,65224;1593,65225,65226,65227,65228;1594,65229,65230,65231,65232;1601,65233,65234,65235,65236;1602,65237,65238,65239,65240;1603,65241,65242,65243,65244;1604,65245,65246,65247,65248;1605,65249,65250,65251,65252;1606,65253,65254,65255,65256;1607,65257,65258,65259,65260;1608,65261,65262,0,0;1609,65263,65264,64488,64489;1610,65265,65266,65267,65268;1657,64358,64359,64360,64361;1658,64350,64351,64352,64353;1659,64338,64339,64340,64341;1662,64342,64343,64344,64345;1663,64354,64355,64356,64357;1664,64346,64347,64348,64349;1667,64374,64375,64376,64377;1668,64370,64371,64372,64373;1670,64378,64379,64380,64381;1671,64382,64383,64384,64385;1672,64392,64393,0,0;1676,64388,64389,0,0;1677,64386,64387,0,0;1678,64390,64391,0,0;1681,64396,64397,0,0;1688,64394,64395,0,0;1700,64362,64363,64364,64365;1702,64366,64367,64368,64369;1705,64398,64399,64400,64401;1709,64467,64468,64469,64470;1711,64402,64403,64404,64405;1713,64410,64411,64412,64413;1715,64406,64407,64408,64409;1722,64414,64415,0,0;1723,64416,64417,64418,64419;1726,64426,64427,64428,64429;1734,64473,64474,0,0;1735,64471,64472,0,0;1736,64475,64476,0,0;1739,64478,64479,0,0;1740,64508,64509,64510,0;1744,64484,64485,64486,64487"
    t = {}
    for each rec in data.Tokenize(";")
        parts = []
        for each p in rec.Tokenize(",")
            parts.push(Int(Val(p)))
        end for
        t[parts[0].ToStr()] = [parts[1], parts[2], parts[3], parts[4]]
    end for
    m.arTbl = t
    return t
end function

function arLig(c as Integer) as Integer
    if c = 1570 then return 65269
    if c = 1571 then return 65271
    if c = 1573 then return 65273
    if c = 1575 then return 65275
    return 0
end function

function arMirror(c as Integer) as Integer
    if c = 40 then return 41
    if c = 41 then return 40
    if c = 91 then return 93
    if c = 93 then return 91
    if c = 123 then return 125
    if c = 125 then return 123
    if c = 60 then return 62
    if c = 62 then return 60
    if c = 171 then return 187
    if c = 187 then return 171
    return c
end function

' "A" Arabic letter, "X" ignorable mark, "W" digit, "N" neutral, "L" other letter
function arType(c as Integer, tbl as Object) as String
    if tbl.DoesExist(c.ToStr()) then return "A"
    if (c >= 1611 and c <= 1631) or c = 1648 or c = 1600 then return "X"
    if (c >= 48 and c <= 57) or (c >= 1632 and c <= 1641) or (c >= 1776 and c <= 1785) then return "W"
    if c <= 32 then return "N"
    if (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126) then return "N"
    if c = 160 or c = 171 or c = 187 or c = 1548 or c = 1563 or c = 1567 or (c >= 1642 and c <= 1645) then return "N"
    return "L"
end function

' joins one right-to-left run and returns its code points in visual order
function arShapeRun(cs as Object, tbl as Object) as Object
    out = []
    connect = false
    n = cs.Count()
    i = 0
    while i < n
        c = cs[i]
        key = c.ToStr()
        if tbl.DoesExist(key) then
            lg = 0
            if c = 1604 and i + 1 < n then lg = arLig(cs[i + 1])
            if lg > 0 then
                if connect then
                    out.push(lg + 1)
                else
                    out.push(lg)
                end if
                connect = false
                i = i + 2
            else
                f = tbl[key]
                nxtOk = false
                if i + 1 < n then
                    nk = cs[i + 1].ToStr()
                    if tbl.DoesExist(nk) then
                        nf = tbl[nk]
                        if nf[1] <> 0 then nxtOk = true
                    end if
                end if
                canF = false
                if f[2] <> 0 and nxtOk then canF = true
                canB = false
                if connect and f[1] <> 0 then canB = true
                g = f[0]
                if g = 0 then g = c
                if canB and canF and f[3] <> 0 then
                    g = f[3]
                else if canB then
                    g = f[1]
                else if canF then
                    g = f[2]
                end if
                out.push(g)
                connect = canF
                i = i + 1
            end if
        else
            out.push(arMirror(c))
            connect = false
            i = i + 1
        end if
    end while
    rev = []
    for k = out.Count() - 1 to 0 step -1
        rev.push(out[k])
    end for
    return rev
end function

function arRunText(rec as Object, tbl as Object) as String
    codes = rec.rc
    if rec.rk = "A" then codes = arShapeRun(rec.rc, tbl)
    s = ""
    for i = 0 to codes.Count() - 1
        s = s + Chr(codes[i])
    end for
    return s
end function

' one line of text -> shaped text in visual (left-to-right) order
function arShape(t as String) as String
    tbl = arTable()
    codes = []
    types = []
    for i = 1 to Len(t)
        c = Asc(Mid(t, i, 1))
        ty = arType(c, tbl)
        if ty <> "X" then
            codes.push(c)
            types.push(ty)
        end if
    end for
    n = codes.Count()

    baseRtl = false
    for i = 0 to n - 1
        if types[i] = "A" then
            baseRtl = true
            exit for
        else if types[i] = "L" then
            exit for
        end if
    end for

    cls = []
    for i = 0 to n - 1
        ty = types[i]
        if ty = "A" then
            cls.push("A")
        else if ty = "L" or ty = "W" then
            cls.push("O")
        else
            ps = ""
            for j = i - 1 to 0 step -1
                if types[j] = "A" or types[j] = "L" then
                    ps = types[j]
                    exit for
                end if
            end for
            ns = ""
            for j = i + 1 to n - 1
                if types[j] = "A" or types[j] = "L" then
                    ns = types[j]
                    exit for
                end if
            end for
            r = "L"
            if baseRtl then r = "A"
            if ps <> "" and ps = ns then r = ps
            if r = "A" then
                cls.push("A")
            else
                cls.push("O")
            end if
        end if
    end for

    runs = []
    i = 0
    while i < n
        k = i
        seg = []
        going = true
        while going
            seg.push(codes[k])
            k = k + 1
            if k >= n then
                going = false
            else if cls[k] <> cls[i] then
                going = false
            end if
        end while
        runs.push({ rk: cls[i], rc: seg })
        i = k
    end while

    out = ""
    if baseRtl then
        for r = runs.Count() - 1 to 0 step -1
            out = out + arRunText(runs[r], tbl)
        end for
    else
        for r = 0 to runs.Count() - 1
            out = out + arRunText(runs[r], tbl)
        end for
    end if
    return out
end function

' multi-line / long text: shaped line by line; long Arabic lines are broken at
' word boundaries first (wrapChars > 0) so the lines still read top to bottom
function arShapeText(t as String, wrapChars as Integer) as String
    lines = []
    cur = ""
    for i = 1 to Len(t)
        ch = Mid(t, i, 1)
        if ch = Chr(10) then
            lines.push(cur)
            cur = ""
        else
            cur = cur + ch
        end if
    end for
    lines.push(cur)

    out = ""
    first = true
    for each ln in lines
        piece = ln
        if hasArabic(ln) then
            if wrapChars > 0 and Len(ln) > wrapChars then
                piece = ""
                chunk = ""
                for each w in ln.Tokenize(" ")
                    if chunk = "" then
                        chunk = w
                    else if Len(chunk) + 1 + Len(w) <= wrapChars then
                        chunk = chunk + " " + w
                    else
                        if piece <> "" then piece = piece + Chr(10)
                        piece = piece + arShape(chunk)
                        chunk = w
                    end if
                end for
                if chunk <> "" then
                    if piece <> "" then piece = piece + Chr(10)
                    piece = piece + arShape(chunk)
                end if
            else
                piece = arShape(ln)
            end if
        end if
        if not first then out = out + Chr(10)
        out = out + piece
        first = false
    end for
    return out
end function

function arFont(size as Integer) as Object
    if m.arFonts = invalid then m.arFonts = {}
    key = "f" + size.ToStr()
    if not m.arFonts.DoesExist(key) then
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/DejaVuSans.ttf"
        f.size = size
        m.arFonts[key] = f
    end if
    return m.arFonts[key]
end function

' Sets label text; Arabic text gets the bundled font and is shaped.
' latFont = the label's normal font (string or Font node); wrapChars 0 = no wrapping help
sub setRtl(lbl as Object, text as String, latFont as Dynamic, size as Integer, wrapChars as Integer)
    if hasArabic(text) then
        lbl.font = arFont(size)
        lbl.text = arShapeText(text, wrapChars)
    else
        if latFont <> invalid then lbl.font = latFont
        lbl.text = text
    end if
end sub

' ---------------------------------------------------------------------
' Debug log, and text the Roku itself draws (it has no Arabic glyphs)
' ---------------------------------------------------------------------

sub logLine(text as String)
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    ts = Right("0" + dt.GetHours().ToStr(), 2) + ":" + Right("0" + dt.GetMinutes().ToStr(), 2) + ":" + Right("0" + dt.GetSeconds().ToStr(), 2)
    print "SBWatch "; ts; "  "; text
end sub

function looksLikeError(t as String) as Boolean
    l = LCase(t)
    if Instr(1, l, "error") > 0 then return true
    if Instr(1, l, "could not") > 0 then return true
    if Instr(1, l, "failed") > 0 then return true
    if Instr(1, l, "rejected") > 0 then return true
    if Instr(1, l, "unavailable") > 0 then return true
    if Instr(1, l, "no sound") > 0 then return true
    return false
end function

' dialog titles and the video player's own title bar use Roku's system font:
' keep Arabic titles out of them
function dlgTitle(t as String, fallback as String) as String
    if hasArabic(t) then return fallback
    return t
end function

function nodeTitle(t as String) as String
    if hasArabic(t) then return ""
    return t
end function

function audioWarn(a as String) as String
    l = LCase(a)
    if Instr(1, l, "dts") > 0 or Instr(1, l, "dca") > 0 or Instr(1, l, "truehd") > 0 or Instr(1, l, "mlp") > 0 then
        return "The Roku cannot play " + a + " audio, so this title will probably have no sound."
    end if
    return ""
end function
