' =====================================================================
' Temporary list sorting (included by MainScene; shares its "m")
' B on a channel / movie / series list cycles through the orders that make
' sense for that list. Nothing is saved: opening another list, or the same
' list again, restores the provider's order.
'   Title A-Z / Z-A       always
'   Newest / oldest       Xtream "added" (series: "last modified")
'   Rating                movies and series
'   Year                  when the provider gives one
' =====================================================================

' one list item as a plain record (used to rebuild a list in a new order)
function itemAA(ch as Object) as Object
    it = { id: ch.id, title: ch.title, HDPosterUrl: ch.HDPosterUrl }
    for each f in ["rating", "ext", "dur", "plot", "season", "epnum", "et", "rkey", "added", "year", "cname"]
        if ch.hasField(f) then it[f] = ch.getField(f)
    end for
    return it
end function

function listHasValue(c as Object, field as String) as Boolean
    n = c.getChildCount()
    if n > 100 then n = 100
    for i = 0 to n - 1
        v = nodeStr(c.getChild(i), field)
        if v <> "" and v <> "0" then return true
    end for
    return false
end function

function sortOptions(c as Object) as Object
    opts = []
    opts.push({ label: "Title A to Z", k: "title", d: false })
    opts.push({ label: "Title Z to A", k: "title", d: true })
    if listHasValue(c, "added") then
        if m.listKind = "series" then
            opts.push({ label: "Recently updated first", k: "added", d: true })
            opts.push({ label: "Least recently updated first", k: "added", d: false })
        else
            opts.push({ label: "Newest added first", k: "added", d: true })
            opts.push({ label: "Oldest added first", k: "added", d: false })
        end if
    end if
    if m.mode <> "live" and listHasValue(c, "rating") then
        opts.push({ label: "Highest rated first", k: "rating", d: true })
        opts.push({ label: "Lowest rated first", k: "rating", d: false })
    end if
    if listHasValue(c, "year") then
        opts.push({ label: "Newest year first", k: "year", d: true })
        opts.push({ label: "Oldest year first", k: "year", d: false })
    end if
    opts.push({ label: "Original order", k: "orig", d: false })
    return opts
end function

sub cycleSort()
    c = m.chList.content
    if c = invalid then return
    lk = m.listKind
    if c.getChildCount() < 2 or lk = "seasons" or lk = "episodes" then
        showStatus("Nothing to sort here", 2)
        return
    end if

    ' a list that was not produced by the last sort starts a new cycle
    fresh = true
    if m.sortCur <> invalid then
        if c.IsSameNode(m.sortCur) then fresh = false
    end if
    if fresh then
        m.sortBase = c
        m.sortIdx = -1
    end if

    opts = sortOptions(m.sortBase)
    m.sortIdx = m.sortIdx + 1
    if m.sortIdx >= opts.Count() then m.sortIdx = 0
    opt = opts[m.sortIdx]

    node = buildSorted(m.sortBase, opt)
    m.sortCur = node
    m.chList.content = node
    m.chList.jumpToItem = 0
    showStatus("Sorted: " + opt.label + "     (B: next order - not saved)", 4)
end sub

function buildSorted(base as Object, opt as Object) as Object
    if opt.k = "orig" then return base
    n = base.getChildCount()
    rows = []
    for i = 0 to n - 1
        ch = base.getChild(i)
        key = ""
        if opt.k = "title" then
            key = LCase(stripResume(chanName(ch)))
        else if opt.k = "added" then
            key = Int(Val(nodeStr(ch, "added")))
        else if opt.k = "rating" then
            key = Val(nodeStr(ch, "rating"))
        else if opt.k = "year" then
            key = Int(Val(nodeStr(ch, "year")))
        end if
        rows.push({ i: i, k: key })
    end for

    sorted = mergeRows(rows, opt.d)
    items = []
    for each r in sorted
        items.push(itemAA(base.getChild(r.i)))
    end for
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    return root
end function

' stable merge sort of { i, k } rows; k is all strings or all numbers
function mergeRows(rows as Object, desc as Boolean) as Object
    n = rows.Count()
    if n < 2 then return rows
    half = n \ 2
    la = []
    ra = []
    for i = 0 to n - 1
        if i < half then
            la.push(rows[i])
        else
            ra.push(rows[i])
        end if
    end for
    la = mergeRows(la, desc)
    ra = mergeRows(ra, desc)

    out = []
    i = 0
    j = 0
    nl = la.Count()
    nr = ra.Count()
    while i < nl and j < nr
        takeLeft = true
        if desc then
            if ra[j].k > la[i].k then takeLeft = false
        else
            if ra[j].k < la[i].k then takeLeft = false
        end if
        if takeLeft then
            out.push(la[i])
            i = i + 1
        else
            out.push(ra[j])
            j = j + 1
        end if
    end while
    while i < nl
        out.push(la[i])
        i = i + 1
    end while
    while j < nr
        out.push(ra[j])
        j = j + 1
    end while
    return out
end function
