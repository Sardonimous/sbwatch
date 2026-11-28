' =====================================================================
' Search (included by MainScene; shares its "m" scope)
'  - Channel search: whole provider, using an on-device name index that
'    IndexTask builds once (category by category) and refreshes every
'    few days. "kind" is generic so VOD / Series can reuse all of it.
'  - Guide search: program titles for the channels of the list that is
'    currently open (guide data is fetched for those channels first).
' Results are shown in the normal channel list, so playing, favorites,
' the guide and the now/next panel all work on them.
' =====================================================================

sub searchInit()
    m.lastQuery = ""
    m.pendingQuery = ""
    m.idxBuilding = false
    m.idxWorkers = []
    m.idxProg = []
    m.idxFinished = 0
    m.idxTotal = 0
    m.idxFails = 0
    m.idxItems = 0
    m.idxSkipped = 0
    m.idxFull = false
    m.idxLabel = m.top.findNode("idxStatus")
    m.sdlg = invalid
    m.es = invalid
    m.esIds = {}
    m.pendingResults = invalid
    m.catMap = {}
    m.autoRebuilt = false
    m.searchActs = []
    m.searchCats = []
    m.searchScopeCat = ""
    m.searchScopeName = ""
    m.idxKind = "live"
    m.idxNoun = "channels"
end sub

' ---------------- index state ----------------

function readIndexMeta(kind as String) as Object
    s = regRead("idxmeta_" + kind)
    if s = "" then return invalid
    j = ParseJson(s)
    if type(j) <> "roAssociativeArray" then return invalid
    return j
end function

' "none" (missing / other provider), "stale" (> 3 days) or "ok"
function indexState(kind as String) as String
    j = readIndexMeta(kind)
    if j = invalid then return "none"
    if toS(j.key) <> m.server + "|" + m.user then return "none"
    if Int(Val(toS(j.ver))) < 4 then return "none"
    if nowSecs() - Int(Val(toS(j.ts))) > 259200 then return "stale"
    return "ok"
end function

sub maybeBuildIndex()
    if m.mode <> "live" then return
    if indexState("live") <> "ok" then startIndexBuild("live", allCatIds(), false)
end sub

' Indexes the given categories with up to 4 workers at once. Categories whose
' index is already recent are skipped unless force is set.
sub startIndexBuild(kind as String, cats as Object, force as Boolean)
    if kind <> m.mode then return
    if m.idxBuilding then
        showStatus("A search index is already being built", 3)
        return
    end if
    n = cats.Count()
    if n = 0 then return

    workers = 4
    if n < workers then workers = n
    slices = []
    for w = 0 to workers - 1
        slices.push([])
    end for
    for i = 0 to n - 1
        slices[i mod workers].push(cats[i])
    end for

    m.idxWorkers = []
    m.idxProg = []
    for w = 0 to workers - 1
        t = CreateObject("roSGNode", "IndexTask")
        t.id = "w" + w.ToStr()
        t.kind = kind
        t.server = m.server
        t.user = m.user
        t.pass = m.pass
        t.key = m.server + "|" + m.user
        t.cats = slices[w]
        t.force = force
        t.cleanup = (w = 0)
        t.observeField("progress", "onIdxProgress")
        t.observeField("state", "onIdxState")
        m.idxWorkers.push(t)
        m.idxProg.push(0)
    end for

    m.idxKind = kind
    m.idxNoun = kindNoun(kind)
    m.idxTotal = n
    m.idxFinished = 0
    m.idxFails = 0
    m.idxItems = 0
    m.idxSkipped = 0
    m.idxFull = (n = m.allCats.Count())
    m.idxBuilding = true
    m.partialRetried = true
    m.idxLabel.text = "Indexing " + m.idxNoun + " 0/" + n.ToStr()
    m.idxLabel.visible = true
    for each t in m.idxWorkers
        t.control = "RUN"
    end for
end sub

sub onIdxProgress(event as Object)
    if not m.idxBuilding then return
    t = event.getRoSGNode()
    w = Int(Val(Mid(t.id, 2)))
    if w < 0 or w >= m.idxProg.Count() then return
    m.idxProg[w] = event.getData()
    done = 0
    for each p in m.idxProg
        done = done + p
    end for
    m.idxLabel.text = "Indexing " + m.idxNoun + " " + done.ToStr() + "/" + m.idxTotal.ToStr()
end sub

sub onIdxState(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    if not m.idxBuilding then return
    res = t.result
    if res <> invalid then
        m.idxFails = m.idxFails + res.fails
        m.idxItems = m.idxItems + res.items
        m.idxSkipped = m.idxSkipped + res.skipped
    end if
    m.idxFinished = m.idxFinished + 1
    if m.idxFinished >= m.idxWorkers.Count() then finishIndexBuild()
end sub

sub finishIndexBuild()
    m.idxBuilding = false
    m.idxLabel.visible = false
    kind = m.idxKind
    if kind = "live" and m.idxFull and m.idxFails = 0 then
        regWrite("idxmeta_live", FormatJson({ ts: nowSecs(), ver: 4, key: m.server + "|" + m.user }))
    end if

    q = m.pendingQuery
    m.pendingQuery = ""
    if q <> "" and kind = m.mode then
        if m.idxFails > 0 then showStatus(m.idxFails.ToStr() + " categories could not be indexed - searching the rest", 3)
        runSearchTask(q)
    else
        note = ""
        if m.idxFails > 0 then note = "  (" + m.idxFails.ToStr() + " categories could not be read)"
        showStatus("Search index ready: " + m.idxItems.ToStr() + " new " + kindNoun(kind) + " indexed" + note, 5)
    end if
end sub

sub cancelSearchWork()
    m.pendingQuery = ""
    m.es = invalid
    m.esIds = {}
    m.pendingResults = invalid
    for each t in m.idxWorkers
        t.control = "STOP"
    end for
    m.idxWorkers = []
    m.idxBuilding = false
    m.idxLabel.visible = false
end sub

' ---------------- dialog ----------------

sub openSearchDialog()
    m.searchScopeCat = ""
    m.searchScopeName = ""
    buildSearchDialog()
end sub

' A on a category row: search inside that one category only
sub searchFocusedCategory()
    c0 = m.catList.content
    if c0 = invalid then return
    cat = c0.getChild(m.catList.itemFocused)
    if cat = invalid then return
    if cat.id = "__search" then
        openSearchDialog()
        return
    end if
    if Left(cat.id, 2) = "__" then
        showStatus("Highlight a category to search inside it", 3)
        return
    end if
    m.searchScopeCat = cat.id
    m.searchScopeName = cat.title
    buildSearchDialog()
end sub

sub buildSearchDialog()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Search"
    if m.mode <> "live" then dlg.title = "Search " + modeName()
    if m.searchScopeCat <> "" then
        dlg.title = dlg.title + "  (highlighted category only)"
    else if m.catFilter <> "" then
        dlg.title = dlg.title + "  (category filter on)"
    end if
    dlg.text = m.lastQuery
    setVoiceGeneric(dlg, "search")
    if m.mode = "live" then
        dlg.buttons = ["Search channels", "Search program guide (current channel list)", "Rebuild channel search index"]
        m.searchActs = ["chan", "epg", "rebuild"]
    else
        noun = kindNoun(m.mode)
        dlg.buttons = ["Search " + noun, "Rebuild " + noun + " search index"]
        m.searchActs = ["chan", "rebuild"]
    end if
    dlg.observeField("buttonSelected", "onSearchButton")
    m.sdlg = dlg
    m.top.dialog = dlg
    setVoiceGeneric(dlg, "search, shown")
end sub

sub onSearchButton(event as Object)
    idx = event.getData()
    txt = m.sdlg.text
    if txt = invalid then txt = ""
    m.sdlg.close = true
    if idx < 0 or idx >= m.searchActs.Count() then return
    act = m.searchActs[idx]

    if act = "rebuild" then
        cats = scopeCats()
        if cats.Count() = 0 then
            showStatus("No categories match the filter", 3)
            return
        end if
        showStatus("Rebuilding the index for " + cats.Count().ToStr() + " categories ...", 4)
        startIndexBuild(m.mode, cats, true)
        return
    end if

    m.lastQuery = txt.Trim()
    q = LCase(m.lastQuery)
    if q = "" then
        showStatus("Type something to search for", 3)
        return
    end if

    if act = "chan" then
        startChannelSearch(q)
    else
        startEpgSearch(q)
    end if
end sub

' ---------------- channel search ----------------

' The category filter limits both what is indexed and what is searched.
sub startChannelSearch(q as String)
    cats = scopeCats()
    if cats.Count() = 0 then
        showStatus("No categories match the filter - clear the filter to search everything", 4)
        return
    end if
    if m.idxBuilding then
        if m.idxKind <> m.mode then
            showStatus("Another search index is being built - try again in a moment", 4)
            return
        end if
        m.pendingQuery = q
        m.searchCats = cats
        showStatus("The search index is still being built - your search will run when it is ready", 0)
        return
    end if

    m.pendingQuery = q
    m.searchCats = cats
    showStatus("Preparing the search ...", 0)
    ' categories that are already indexed are skipped, so this is quick when up to date
    startIndexBuild(m.mode, cats, false)
end sub

sub runSearchTask(q as String)
    kind = m.mode
    scope = ""
    if m.searchScopeName <> "" then
        scope = " in " + m.searchScopeName
    else if m.catFilter <> "" then
        scope = " in " + m.searchCats.Count().ToStr() + " categories"
    end if
    showStatus("Searching" + scope + " ...", 0)
    t = CreateObject("roSGNode", "SearchTask")
    t.kind = kind
    t.query = q
    t.key = m.server + "|" + m.user
    t.cats = m.searchCats
    t.catMap = m.catMap
    t.observeField("state", "onSearchDone")
    m.srchTask = t
    t.control = "RUN"
end sub

sub onSearchDone(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    q = t.query
    kind = t.kind
    if kind <> m.mode then return

    if t.errorMsg <> "" then
        showStatus("Search failed: " + t.errorMsg, 5)
        return
    end if

    ' Self-heal: categories whose index files are damaged or incomplete are
    ' rebuilt (once per session) and the search is run again.
    if not m.autoRebuilt and t.bad.Count() > 0 then
        m.autoRebuilt = true
        m.pendingQuery = q
        showStatus("Part of the search index was damaged - rebuilding " + t.bad.Count().ToStr() + " categories", 0)
        startIndexBuild(kind, t.bad, true)
        return
    end if

    noun = kindNoun(kind)
    node = t.content
    shown = node.getChildCount()
    scope = ""
    if m.searchScopeName <> "" then
        scope = "  (in " + m.searchScopeName + ")"
    else if m.catFilter <> "" then
        scope = "  (categories matching the filter)"
    end if
    label = t.total.ToStr() + " " + noun + " match '" + q + "'" + scope
    if t.total = 0 then label = zeroNote(q, t.indexed, kind, t.missing)
    if t.total > shown then label = "Showing " + shown.ToStr() + " of " + t.total.ToStr() + " " + noun + " matching '" + q + "' - refine your search" + scope
    deliverResults(node, label, "No " + noun + " match '" + q + "'")
end sub

' ---------------- guide (EPG) search ----------------

sub startEpgSearch(q as String)
    c = m.chList.content
    if c = invalid then
        showStatus("Open a category first, then search its guide", 4)
        return
    end if
    n = c.getChildCount()
    if n = 0 then
        showStatus("Open a category first, then search its guide", 4)
        return
    end if
    if n > 600 then n = 600

    words = []
    for each w in q.Tokenize(" ")
        words.push(w)
    end for

    snap = []
    need = {}
    for i = 0 to n - 1
        item = c.getChild(i)
        ic = item.HDPosterUrl
        if ic = invalid then ic = ""
        snap.push({ id: item.id, name: chanName(item), icon: ic })
        if cachedEpg(item.id) = invalid then need[item.id] = true
    end for

    m.es = { q: q, words: words, snap: snap, total: need.Count() }
    m.esIds = need
    if need.Count() = 0 then
        finishEpgSearch()
        return
    end if

    showStatus("Searching guide ...  0 / " + need.Count().ToStr(), 0)
    for each id in need.Keys()
        requestEpg(id)
    end for
end sub

sub esTick(id as String)
    if m.es = invalid then return
    if not m.esIds.DoesExist(id) then return
    m.esIds.Delete(id)
    remaining = m.esIds.Count()
    if remaining = 0 then
        finishEpgSearch()
    else
        done = m.es.total - remaining
        showStatus("Searching guide ...  " + done.ToStr() + " / " + m.es.total.ToStr(), 0)
    end if
end sub

sub finishEpgSearch()
    es = m.es
    m.es = invalid
    m.esIds = {}
    if es = invalid then return

    now = nowSecs()
    items = []
    for each ch in es.snap
        if m.epgCache.DoesExist(ch.id) then
            for each l in m.epgCache[ch.id].listings
                if l.stop > now and items.Count() < 300 then
                    low = LCase(l.title)
                    good = true
                    for each w in es.words
                        if Instr(1, low, w) = 0 then good = false
                    end for
                    if good then
                        pre = ""
                        if l.start <= now then pre = "NOW  "
                        items.push({
                            id: ch.id
                            title: pre + l.title + "     " + fmtDayTime(l.start) + "  |  " + ch.name
                            cname: ch.name
                            HDPosterUrl: ch.icon
                            start: l.start
                        })
                    end if
                end if
            end for
        end if
    end for
    for i = 1 to items.Count() - 1
        cur = items[i]
        j = i - 1
        moving = true
        while moving
            if j < 0 then
                moving = false
            else if items[j].start > cur.start then
                items[j + 1] = items[j]
                j = j - 1
            else
                moving = false
            end if
        end while
        items[j + 1] = cur
    end for

    node = CreateObject("roSGNode", "ContentNode")
    node.update({ children: items }, true)
    deliverResults(node, items.Count().ToStr() + " programs match '" + es.q + "'", "No program titles match '" + es.q + "' in this list's guide data")
end sub

' ---------------- showing results ----------------

sub deliverResults(node as Object, label as String, emptyMsg as String)
    if m.video.visible or m.guideOpen or m.detailOpen then
        m.pendingResults = { node: node, label: label, emptyMsg: emptyMsg }
        showStatus(label + "  (close the player / guide to view)", 6)
        return
    end if
    m.curCat = "__search"
    m.navStack = []
    if m.mode = "vod" then
        m.listKind = "movies"
        decorateResume(node, "m")
    else if m.mode = "series" then
        m.listKind = "series"
    else
        m.listKind = "channels"
    end if
    showChannels(node, emptyMsg)
    showStatus(label, 6)
end sub

sub showPendingResults()
    if m.pendingResults = invalid then return
    if m.video.visible or m.guideOpen then return
    r = m.pendingResults
    m.pendingResults = invalid
    deliverResults(r.node, r.label, r.emptyMsg)
end sub

' Explains an empty result: how big the index is and whether it is incomplete.
function zeroNote(q as String, indexed as Integer, kind as String, missing as Integer) as String
    s = "0 of " + indexed.ToStr() + " indexed " + kindNoun(kind) + " match '" + q + "'"
    if m.searchScopeName <> "" then
        s = s + " (in " + m.searchScopeName + ")"
    else if m.catFilter <> "" then
        s = s + " (in the categories matching the filter)"
    end if
    if missing > 0 then s = s + " - " + missing.ToStr() + " categories could not be indexed; use Rebuild index"
    return s
end function

' ids of the categories the search covers: those matching the category filter
' (all of them when no filter is set)
function scopeCats() as Object
    if m.searchScopeCat <> "" then return [m.searchScopeCat]
    ids = []
    words = []
    if m.catFilter <> "" then
        for each w in m.catFilter.Tokenize(" ")
            words.push(w)
        end for
    end if
    for each c in m.allCats
        low = LCase(c.title)
        good = true
        for each w in words
            if Instr(1, low, w) = 0 then good = false
        end for
        if good then ids.push(c.id)
    end for
    return ids
end function

function allCatIds() as Object
    ids = []
    for each c in m.allCats
        ids.push(c.id)
    end for
    return ids
end function
