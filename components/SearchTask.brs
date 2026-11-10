sub init()
    m.top.functionName = "run"
end sub

sub run()
    m.top.errorMsg = ""
    path = "cachefs:/svidx_" + m.top.kind + ".txt"
    fs = CreateObject("roFileSystem")
    if not fs.Exists(path) then
        m.top.errorMsg = "index missing"
        return
    end if
    txt = ReadAsciiFile(path)
    if txt = "" then
        m.top.errorMsg = "index missing"
        return
    end if

    words = []
    for each w in m.top.query.Tokenize(" ")
        words.push(w)
    end for
    if words.Count() = 0 then
        m.top.errorMsg = "empty query"
        return
    end if

    cm = m.top.catMap
    sep = Chr(9)
    first = []
    rest = []
    total = 0
    cap = 500

    lines = txt.Tokenize(Chr(10))
    for each ln in lines
        p1 = Instr(1, ln, sep)
        if p1 > 0 then
            p2 = Instr(p1 + 1, ln, sep)
            if p2 > 0 then
                p3 = Instr(p2 + 1, ln, sep)
                icon = ""
                if p3 > 0 then
                    name = Mid(ln, p2 + 1, p3 - p2 - 1)
                    icon = Mid(ln, p3 + 1)
                else
                    name = Mid(ln, p2 + 1)
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
                        cid = Mid(ln, p1 + 1, p2 - p1 - 1)
                        cn = cm.Lookup(cid)
                        title = name
                        if cn <> invalid then title = name + "     [" + cn + "]"
                        item = { id: Left(ln, p1 - 1), title: title, cname: name, HDPosterUrl: icon }
                        if isFirst then
                            first.push(item)
                        else
                            rest.push(item)
                        end if
                    end if
                end if
            end if
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
    m.top.total = total
    m.top.content = root
end sub
