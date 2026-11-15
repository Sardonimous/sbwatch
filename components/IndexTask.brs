' Builds a compact on-device name index (one line per channel/title):
'     id <TAB> categoryId <TAB> name <TAB> logoUrl
' The provider is walked category by category (each retried up to 3 times),
' the lines are collected in memory, then stored as several small "shard"
' files that are each read back and verified. Any old index files are wiped
' first. If the app cache cannot hold the shards reliably, tmp:/ is used.
' kind: "live" | "vod" | "series"  (vod/series are ready for later)

sub init()
    m.top.functionName = "run"
end sub

function fetchCategory(base as String, cid as String, idField as String, iconField as String) as Dynamic
    sep = Chr(9)
    body = httpFetch(base + urlEnc(cid), 45000)
    if body = invalid then return invalid
    json = ParseJson(body)
    if type(json) <> "roArray" then return invalid

    chunk = ""
    n = 0
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
                n = n + 1
            end if
        end if
    end for
    return { chunk: chunk, n: n }
end function

' Deletes every index file (any generation / format) from both volumes.
sub cleanIndexFiles()
    for each vol in ["cachefs:/", "tmp:/"]
        names = ListDir(vol)
        if names <> invalid then
            for each nm in names
                if Left(LCase(nm), 5) = "svidx" then DeleteFile(vol + nm)
            end for
        end if
    end for
end sub

' "cachefs:/ 3 files 120 KB; tmp:/ 0 files 0 KB" - for error messages
function usageNote() as String
    fs = CreateObject("roFileSystem")
    out = ""
    for each vol in ["cachefs:/", "tmp:/"]
        names = ListDir(vol)
        n = 0
        bytes = 0
        if names <> invalid then
            for each nm in names
                n = n + 1
                st = fs.Stat(vol + nm)
                if st <> invalid then
                    if st.DoesExist("size") then bytes = bytes + Int(Val(toS(st.size)))
                end if
            end for
        end if
        out = out + vol + " holds " + n.ToStr() + " files / " + Int(bytes / 1024).ToStr() + " KB;  "
    end for
    return out
end function

' Writes and verifies every shard on one volume. Returns "" or an error text.
function writeShards(vol as String, shards as Object, kind as String) as String
    for i = 0 to shards.Count() - 1
        p = vol + "svidx_" + kind + "_" + i.ToStr() + ".txt"
        if not WriteAsciiFile(p, shards[i]) then
            return "write failed for part " + i.ToStr() + " on " + vol
        end if
        back = ReadAsciiFile(p)
        if back <> shards[i] then
            return "verify failed for part " + i.ToStr() + " on " + vol + " (wrote " + Len(shards[i]).ToStr() + " chars, read back " + Len(back).ToStr() + ")"
        end if
    end for
    return ""
end function

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

    ids = m.top.cats
    total = ids.Count()
    count = 0
    fails = 0
    shards = []
    buf = ""

    for i = 0 to total - 1
        cid = ids[i]
        res = invalid
        for attempt = 1 to 3
            res = fetchCategory(base, cid, idField, iconField)
            if res <> invalid then exit for
            if attempt < 3 then sleep(600 * attempt)
        end for

        if res = invalid then
            fails = fails + 1
        else
            count = count + res.n
            buf = buf + res.chunk
            if Len(buf) > 120000 then
                shards.push(buf)
                buf = ""
            end if
        end if
        m.top.progress = i + 1
    end for
    if buf <> "" then shards.push(buf)

    if count = 0 or fails * 2 > total then
        m.top.result = { ok: false, count: count, fails: fails, shards: 0, vol: "", err: fails.ToStr() + " of " + total.ToStr() + " categories failed" }
        return
    end if

    ' start from a clean slate, then store + verify (cache first, tmp second)
    cleanIndexFiles()
    vol = ""
    errs = ""
    for each v in ["cachefs:/", "tmp:/"]
        e = writeShards(v, shards, kind)
        if e = "" then
            vol = v
            exit for
        end if
        errs = errs + e + ";  "
        cleanIndexFiles()
    end for

    if vol = "" then
        m.top.result = { ok: false, count: count, fails: fails, shards: 0, vol: "", err: "cannot store the index: " + errs + usageNote() }
        return
    end if
    m.top.result = { ok: true, count: count, fails: fails, shards: shards.Count(), vol: vol, err: "" }
end sub
