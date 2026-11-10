' =====================================================================
' Search (included by MainScene; shares its "m" scope)
'  - Channel search: whole provider, using an on-device name index that
'    IndexTask builds once (category by category) and refreshes every
'    few days. "kind" is generic so VOD / Series can reuse all of it.
'  - Guide search: programme titles for the channels of the list that is
'    currently open (guide data is fetched for those channels first).
' Results are shown in the normal channel list, so playing, favorites,
' the guide and the now/next panel all work on them.
' =====================================================================

sub searchInit()
    m.lastQuery = ""
    m.pendingQuery = ""
    m.idxBuilding = false
    m.idxTask = invalid
    m.idxTotal = 0
    m.idxLabel = m.top.findNode("idxStatus")
    m.sdlg = invalid
    m.es = invalid
    m.esIds = {}
    m.pendingResults = invalid
    m.catMap = {}
end sub

' ---------------- index state ----------------

function readIndexMeta(kind as String) as Object
    path = "cachefs:/svidx_" + kind + ".meta"
    fs = CreateObject("roFileSystem")
    if not fs.Exists(path) then return invalid
    s = ReadAsciiFile(path)
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
    fs = CreateObject("roFileSystem")
    if not fs.Exists("cachefs:/svidx_" + kind + ".txt") then return "none"
    if Int(Val(toS(j.ver))) < 2 then return "stale"
    age = nowSecs() - Int(Val(toS(j.ts)))
    if age > 259200 then return "stale"
    return "ok"
end function

sub maybeBuildIndex()
    if indexState("live") <> "ok" then startIndexBuild()
end sub

sub startIndexBuild()
    if m.idxBuilding then
        showStatus("Search index is already being built", 3)
        return
    end if
    if m.allCats.Count() = 0 then return

    ids = []
    m.catMap = {}
    for each c in m.allCats
        ids.push(c.id)
        m.catMap[c.id] = c.title
    end for

    t = CreateObject("roSGNode", "IndexTask")
    t.kind = "live"
    t.server = m.server
    t.user = m.user
    t.pass = m.pass
    t.cats = ids
    t.observeField("progress", "onIdxProgress")
    t.observeField("state", "onIdxState")
    m.idxTask = t
    m.idxTotal = ids.Count()
    m.idxBuilding = true
    m.idxLabel.text = "Indexing channels 0/" + m.idxTotal.ToStr()
    m.idxLabel.visible = true
    t.control = "RUN"
end sub

sub onIdxProgress(event as Object)
    if not m.idxBuilding then return
    m.idxLabel.text = "Indexing channels " + event.getData().ToStr() + "/" + m.idxTotal.ToStr()
end sub

sub onIdxState(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    if m.idxTask = invalid then return
    if not t.IsSameNode(m.idxTask) then return

    m.idxBuilding = false
    m.idxLabel.visible = false
    res = t.result
    if res = invalid then
        m.pendingQuery = ""
        return
    end if
    if not res.ok then
        m.pendingQuery = ""
        showStatus("Search index failed: " + res.err, 6)
        return
    end if

    q = m.pendingQuery
    m.pendingQuery = ""
    if q <> "" then
        runSearchTask(q)
    else
        showStatus("Search index ready: " + res.count.ToStr() + " channels", 4)
    end if
end sub

sub cancelSearchWork()
    m.pendingQuery = ""
    m.es = invalid
    m.esIds = {}
    m.pendingResults = invalid
    if m.idxTask <> invalid then m.idxTask.control = "STOP"
    m.idxBuilding = false
    m.idxLabel.visible = false
end sub

' ---------------- dialog ----------------

sub openSearchDialog()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Search"
    dlg.message = ["Channels = whole provider.  Guide = programme titles in the channel list that is open now."]
    dlg.text = m.lastQuery
    dlg.buttons = ["Channels", "Guide (this list)", "Rebuild index", "Cancel"]
    dlg.observeField("buttonSelected", "onSearchButton")
    m.sdlg = dlg
    m.top.dialog = dlg
end sub

sub onSearchButton(event as Object)
    idx = event.getData()
    txt = m.sdlg.text
    if txt = invalid then txt = ""
    m.sdlg.close = true

    if idx = 3 then return
    if idx = 2 then
        startIndexBuild()
        return
    end if

    m.lastQuery = txt.Trim()
    q = LCase(m.lastQuery)
    if q = "" then
        showStatus("Type something to search for", 3)
        return
    end if

    if idx = 0 then
        startChannelSearch(q)
    else
        startEpgSearch(q)
    end if
end sub

' ---------------- channel search ----------------

sub startChannelSearch(q as String)
    if m.idxBuilding then
        m.pendingQuery = q
        showStatus("Search index is still being built - your search will run when it is ready", 0)
        return
    end if

    st = indexState("live")
    if st = "none" then
        m.pendingQuery = q
        startIndexBuild()
        showStatus("Building search index (first time only) - your search will run when it is ready", 0)
        return
    end if
    if st = "stale" then startIndexBuild()
    runSearchTask(q)
end sub

sub runSearchTask(q as String)
    showStatus("Searching ...", 0)
    t = CreateObject("roSGNode", "SearchTask")
    t.kind = "live"
    t.query = q
    t.catMap = m.catMap
    t.observeField("state", "onSearchDone")
    m.srchTask = t
    t.control = "RUN"
end sub

sub onSearchDone(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    q = t.query

    if t.errorMsg <> "" then
        if t.errorMsg = "index missing" then
            m.pendingQuery = q
            startIndexBuild()
            showStatus("Rebuilding search index - your search will run when it is ready", 0)
        else
            showStatus("Search failed: " + t.errorMsg, 5)
        end if
        return
    end if

    node = t.content
    shown = node.getChildCount()
    label = t.total.ToStr() + " channels match '" + q + "'"
    if t.total > shown then label = "Showing " + shown.ToStr() + " of " + t.total.ToStr() + " channels matching '" + q + "' - refine your search"
    deliverResults(node, label, "No channels match '" + q + "'")
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
    deliverResults(node, items.Count().ToStr() + " programmes match '" + es.q + "'", "No programme titles match '" + es.q + "' in this list's guide data")
end sub

' ---------------- showing results ----------------

sub deliverResults(node as Object, label as String, emptyMsg as String)
    if m.video.visible or m.guideOpen then
        m.pendingResults = { node: node, label: label, emptyMsg: emptyMsg }
        showStatus(label + "  (close the player / guide to view)", 6)
        return
    end if
    m.curCat = "__search"
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
