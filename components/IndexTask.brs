' =====================================================================
' Search index worker. The scene starts several of these at once, each with
' its own slice of the categories to index.
'
' Per category (kind = live | vod | series):
'   svidx_<kind>_c<cid>_<n>.txt   lines  id <TAB> name [<TAB> logo url (live only)]
'   svidx_<kind>_c<cid>.ok        marker written last:  time TAB pieces TAB count TAB key TAB volume
' A category with a valid, recent marker is skipped (unless force), so only
' missing or old categories are fetched. Data is verified by reading it back;
' the app cache is tried first, tmp:/ second.
' =====================================================================

sub init()
    m.top.functionName = "run"
end sub

function cleanField(s as String, sep as String) as String
    if Instr(1, s, sep) > 0 then s = s.Replace(sep, " ")
    if Instr(1, s, Chr(10)) > 0 then s = s.Replace(Chr(10), " ")
    if Instr(1, s, Chr(13)) > 0 then s = s.Replace(Chr(13), " ")
    return s
end function

function fetchCategory(base as String, cid as String, idField as String, iconField as String, withIcon as Boolean) as Dynamic
    sep = Chr(9)
    body = httpFetch(base + urlEnc(cid), 60000)
    if body = invalid then return invalid
    json = ParseJson(body)
    if type(json) <> "roArray" then return invalid

    pieces = []
    buf = ""
    n = 0
    for each s in json
        if type(s) = "roAssociativeArray" then
            nm = toS(s.name)
            sid = toS(s[idField])
            if nm <> "" and sid <> "" then
                line = sid + sep + cleanField(nm, sep)
                if withIcon then line = line + sep + cleanField(toS(s[iconField]), sep)
                buf = buf + line + Chr(10)
                n = n + 1
                if Len(buf) > 100000 then
                    pieces.push(buf)
                    buf = ""
                end if
            end if
        end if
    end for
    if buf <> "" then pieces.push(buf)
    return { pieces: pieces, n: n }
end function

' old index formats (single shard files etc.) are deleted
sub cleanOldIndexFiles()
    for each vol in ["cachefs:/", "tmp:/"]
        names = ListDir(vol)
        if names <> invalid then
            for each nm in names
                low = LCase(nm)
                if Left(low, 5) = "svidx" then
                    if Instr(7, low, "_c") = 0 then DeleteFile(vol + nm)
                end if
            end for
        end if
    end for
end sub

function markerFresh(fs as Object, kind as String, cid as String, key as String) as Boolean
    for each v in ["cachefs:/", "tmp:/"]
        p = v + "svidx_" + kind + "_c" + fileKey(cid) + ".ok"
        if fs.Exists(p) then
            parts = []
            for each f in ReadAsciiFile(p).Tokenize(Chr(9))
                parts.push(f)
            end for
            if parts.Count() >= 5 then
                if parts[3] = key and nowSecs() - Int(Val(parts[0])) < 259200 then return true
            end if
        end if
    end for
    return false
end function

sub deleteCategoryFiles(fs as Object, kind as String, cid as String)
    base = "svidx_" + kind + "_c" + fileKey(cid)
    for each v in ["cachefs:/", "tmp:/"]
        if fs.Exists(v + base + ".ok") then DeleteFile(v + base + ".ok")
        for n = 0 to 400
            p = v + base + "_" + n.ToStr() + ".txt"
            if not fs.Exists(p) then exit for
            DeleteFile(p)
        end for
    end for
end sub

function storeCategory(fs as Object, kind as String, cid as String, pieces as Object, count as Integer, key as String) as Boolean
    deleteCategoryFiles(fs, kind, cid)
    base = "svidx_" + kind + "_c" + fileKey(cid)
    vol = ""
    volCode = ""
    for each v in ["cachefs:/", "tmp:/"]
        good = true
        for n = 0 to pieces.Count() - 1
            p = v + base + "_" + n.ToStr() + ".txt"
            if not WriteAsciiFile(p, pieces[n]) then
                good = false
                exit for
            end if
            if ReadAsciiFile(p) <> pieces[n] then
                good = false
                exit for
            end if
        end for
        if good then
            vol = v
            volCode = "c"
            if v = "tmp:/" then volCode = "t"
            exit for
        end if
        deleteCategoryFiles(fs, kind, cid)
    end for
    if vol = "" then return false

    sep = Chr(9)
    marker = nowSecs().ToStr() + sep + pieces.Count().ToStr() + sep + count.ToStr() + sep + key + sep + volCode
    return WriteAsciiFile(vol + base + ".ok", marker)
end function

sub run()
    kind = m.top.kind
    action = "get_live_streams"
    idField = "stream_id"
    iconField = "stream_icon"
    withIcon = false
    if kind = "live" then withIcon = true
    if kind = "vod" then
        action = "get_vod_streams"
    else if kind = "series" then
        action = "get_series"
        idField = "series_id"
        iconField = "cover"
    end if

    base = m.top.server + "/player_api.php?username=" + urlEnc(m.top.user) + "&password=" + urlEnc(m.top.pass) + "&action=" + action + "&category_id="
    fs = CreateObject("roFileSystem")
    if m.top.cleanup then cleanOldIndexFiles()

    ids = m.top.cats
    key = m.top.key
    fails = 0
    skipped = 0
    items = 0

    for i = 0 to ids.Count() - 1
        cid = ids[i]
        if not m.top.force and markerFresh(fs, kind, cid, key) then
            skipped = skipped + 1
        else
            res = invalid
            for attempt = 1 to 3
                res = fetchCategory(base, cid, idField, iconField, withIcon)
                if res <> invalid then exit for
                if attempt < 3 then sleep(600 * attempt)
            end for
            if res = invalid then
                fails = fails + 1
            else if storeCategory(fs, kind, cid, res.pieces, res.n, key) then
                items = items + res.n
            else
                fails = fails + 1
            end if
        end if
        m.top.progress = i + 1
    end for
    m.top.result = { ok: true, fails: fails, skipped: skipped, items: items }
end sub
