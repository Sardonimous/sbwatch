' Searches the per-category index files of the given categories (see IndexTask).
sub init()
    m.top.functionName = "run"
end sub

sub run()
    m.top.errorMsg = ""
    words = []
    for each w in m.top.query.Tokenize(" ")
        words.push(w)
    end for
    if words.Count() = 0 then
        m.top.errorMsg = "empty query"
        return
    end if

    kind = m.top.kind
    key = m.top.key
    cm = m.top.catMap
    fs = CreateObject("roFileSystem")
    sep = Chr(9)
    first = []
    rest = []
    bad = []
    total = 0
    scanned = 0
    missing = 0
    cap = 500

    for each cid in m.top.cats
        base = "svidx_" + kind + "_c" + fileKey(cid)
        pieces = 0
        expected = 0
        vol = ""
        for each v in ["cachefs:/", "tmp:/"]
            if vol = "" and fs.Exists(v + base + ".ok") then
                parts = []
                for each f in ReadAsciiFile(v + base + ".ok").Tokenize(Chr(9))
                    parts.push(f)
                end for
                if parts.Count() >= 5 then
                    if parts[3] = key then
                        pieces = Int(Val(parts[1]))
                        expected = Int(Val(parts[2]))
                        vol = v
                    end if
                end if
            end if
        end for

        if vol = "" then
            missing = missing + 1
        else
            catName = cm.Lookup(cid)
            parsed = 0
            damaged = false
            for n = 0 to pieces - 1
                path = vol + base + "_" + n.ToStr() + ".txt"
                if not fs.Exists(path) then
                    damaged = true
                    exit for
                end if
                for each ln in ReadAsciiFile(path).Tokenize(Chr(10))
                    p1 = Instr(1, ln, sep)
                    if p1 > 0 then
                        parsed = parsed + 1
                        p2 = Instr(p1 + 1, ln, sep)
                        icon = ""
                        if p2 > 0 then
                            name = Mid(ln, p1 + 1, p2 - p1 - 1)
                            icon = Mid(ln, p2 + 1)
                        else
                            name = Mid(ln, p1 + 1)
                        end if
                        low = LCase(name)
                        good = true
                        for each w in words
                            if Instr(1, low, w) = 0 then
                                good = false
                                exit for
                            end if
                        end for
                        if good then
                            total = total + 1
                            isFirst = false
                            if Instr(1, low, words[0]) = 1 then isFirst = true
                            if (isFirst and first.Count() < cap) or (not isFirst and rest.Count() < cap) then
                                title = name
                                if catName <> invalid then title = name + "     [" + catName + "]"
                                item = { id: Left(ln, p1 - 1), title: title, cname: name, HDPosterUrl: icon }
                                if isFirst then
                                    first.push(item)
                                else
                                    rest.push(item)
                                end if
                            end if
                        end if
                    end if
                end for
            end for
            scanned = scanned + parsed
            if damaged or parsed <> expected then bad.push(cid)
        end if
    end for

    items = []
    for each it in first
        if items.Count() < cap then items.push(it)
    end for
    for each it in rest
        if items.Count() < cap then items.push(it)
    end for

    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    m.top.indexed = scanned
    m.top.missing = missing
    m.top.bad = bad
    m.top.total = total
    m.top.content = root
end sub
