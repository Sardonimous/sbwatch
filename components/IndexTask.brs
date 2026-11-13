' Builds a compact on-device name index (one line per channel/title):
'     id <TAB> categoryId <TAB> name <TAB> logoUrl
' by walking the provider category by category, so memory stays small.
' Each category is retried (providers sometimes reject rapid requests).
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

    ids = m.top.cats
    total = ids.Count()
    count = 0
    fails = 0
    bytes = 0

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
            if res.chunk <> "" then
                ba = CreateObject("roByteArray")
                ba.FromAsciiString(res.chunk)
                wrote = false
                if fs.Exists(tmp) then
                    wrote = ba.AppendFile(tmp)
                else
                    wrote = ba.WriteFile(tmp)
                end if
                if not wrote then
                    m.top.result = { ok: false, count: 0, fails: fails, err: "could not write cache file" }
                    return
                end if
                bytes = bytes + ba.Count()
            end if
        end if
        m.top.progress = i + 1
    end for

    if count = 0 or fails * 2 > total then
        m.top.result = { ok: false, count: count, fails: fails, err: fails.ToStr() + " of " + total.ToStr() + " categories failed" }
        return
    end if

    if fs.Exists(fin) then fs.Delete(fin)
    if not fs.Rename(tmp, fin) then
        m.top.result = { ok: false, count: count, fails: fails, err: "could not finalize cache file" }
        return
    end if

    st = fs.Stat(fin)
    if st <> invalid then
        if st.DoesExist("size") then
            found = Val(toS(st.size))
            if found < bytes then
                m.top.result = { ok: false, count: count, fails: fails, err: "cache file truncated (wrote " + bytes.ToStr() + " bytes, found " + Int(found).ToStr() + ")" }
                return
            end if
        end if
    end if
    m.top.result = { ok: true, count: count, fails: fails, err: "" }
end sub
