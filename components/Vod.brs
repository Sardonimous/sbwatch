' =====================================================================
' Movies & Series with resume (included by MainScene; shares its "m")
'
'  mode      m.mode = "live" | "vod" (Movies) | "series"
'  lists     m.listKind = channels | movies | series | seasons | episodes | continue
'  nav       m.navStack remembers the list above when drilling into
'            series -> seasons -> episodes (Back pops it)
'  resume    registry key "resume": newest first, max 40 entries / 9 KB
'            { k:"m123"|"e456", p:position s, d:duration s, t:time, n:title,
'              i:icon, x:ext, id, ty:"m"|"e", sid:series id, se:season }
' =====================================================================

sub vodInit()
    m.mode = regRead("mode")
    if m.mode <> "vod" and m.mode <> "series" then m.mode = "live"
    m.listKind = "channels"
    m.navStack = []
    m.detailOpen = false
    m.detail = invalid
    m.detActs = []
    m.vodPlaying = false
    m.vodStarted = false
    m.vod = invalid
    m.seriesData = invalid
    m.pendingItem = invalid
    m.titleLbl = m.top.findNode("title")
    m.vodPoster = m.top.findNode("vodPoster")
    m.vodInfo = m.top.findNode("vodInfo")
    m.detGroup = m.top.findNode("detailView")
    m.detPoster = m.top.findNode("detPoster")
    m.detTitle = m.top.findNode("detTitle")
    m.detMeta = m.top.findNode("detMeta")
    m.detPlot = m.top.findNode("detPlot")
    m.detCast = m.top.findNode("detCast")
    m.detActions = m.top.findNode("detActions")
    m.detActions.observeField("itemSelected", "onDetAction")
    m.resumeTimer = m.top.findNode("resumeTimer")
    m.resumeTimer.observeField("fire", "onResumeTimer")
    updateTitle()
end sub

function modeName() as String
    if m.mode = "vod" then return "Movies"
    if m.mode = "series" then return "Series"
    return "Live TV"
end function

function categoriesAction() as String
    if m.mode = "vod" then return "get_vod_categories"
    if m.mode = "series" then return "get_series_categories"
    return "get_live_categories"
end function

function filterKey() as String
    if m.mode = "live" then return "catfilter"
    return "catfilter_" + m.mode
end function

function kindNoun(kind as String) as String
    if kind = "vod" then return "movies"
    if kind = "series" then return "series"
    return "channels"
end function

function listNoun() as String
    lk = m.listKind
    if lk = "movies" then return "movies"
    if lk = "series" then return "series"
    if lk = "seasons" then return "seasons"
    if lk = "episodes" then return "episodes"
    if lk = "continue" then return "titles"
    return "channels"
end function

sub updateTitle()
    if m.mode = "live" then
        m.titleLbl.text = "SBWatch"
    else
        m.titleLbl.text = "SBWatch  -  " + modeName()
    end if
end sub

' ---------------------------------------------------------------------
' Mode switch (Live TV / Movies / Series)
' ---------------------------------------------------------------------

sub openModeMenu()
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = "Browse"
    dlg.message = ["Currently: " + modeName()]
    dlg.buttons = ["Live TV", "Movies", "Series"]
    dlg.observeField("buttonSelected", "onModeMenu")
    m.modeDlg = dlg
    m.top.dialog = dlg
end sub

sub onModeMenu(event as Object)
    idx = event.getData()
    m.modeDlg.close = true
    newMode = "live"
    if idx = 1 then newMode = "vod"
    if idx = 2 then newMode = "series"
    if newMode = m.mode then return
    switchMode(newMode)
end sub

sub switchMode(newMode as String)
    m.mode = newMode
    regWrite("mode", newMode)
    m.navStack = []
    m.seriesData = invalid
    m.curCat = ""
    m.listKind = "channels"
    m.allCats = []
    m.chList.content = invalid
    m.chName.text = ""
    setLogo(m.chLogo, "")
    m.vodPoster.visible = false
    m.vodInfo.visible = false
    m.epgList.visible = false
    m.epgText.visible = false
    updateTitle()
    showStatus("Loading " + modeName() + " categories ...", 0)
    runTask("categories", apiUrl(categoriesAction(), ""), "", "onCategories")
end sub

' ---------------------------------------------------------------------
' Category selection in Movies / Series
' ---------------------------------------------------------------------

sub vodCatSelected(cat as Object)
    if cat.id = "__cont" then
        m.listKind = "continue"
        showChannels(continueNode(), "Nothing to continue yet. Stop a movie or episode part-way and it will appear here.")
    else if m.mode = "vod" then
        m.listKind = "movies"
        showStatus("Loading movies ...", 0)
        runTask("streams", apiUrl("get_vod_streams", "&category_id=" + urlEnc(cat.id)), cat.id, "onStreams")
    else
        m.listKind = "series"
        showStatus("Loading series ...", 0)
        runTask("series", apiUrl("get_series", "&category_id=" + urlEnc(cat.id)), cat.id, "onStreams")
    end if
end sub

sub vodSelected(idx as Integer)
    c = m.chList.content
    if c = invalid then return
    item = c.getChild(idx)
    if item = invalid then return
    lk = m.listKind
    if lk = "movies" then
        openMovie(item)
    else if lk = "series" then
        openSeries(item)
    else if lk = "seasons" then
        openSeason(item)
    else if lk = "episodes" then
        openEpisode(item)
    else if lk = "continue" then
        openContinue(item)
    end if
end sub

' title without the "   (resume 12:34)" suffix and without a search-result category tag
function baseTitle(item as Object) as String
    t = chanName(item)
    p = Instr(1, t, "   (resume ")
    if p > 0 then t = Left(t, p - 1)
    return t
end function

' ---------------------------------------------------------------------
' Right-hand panel for Movies / Series
' ---------------------------------------------------------------------

sub updateVodPanel(item as Object)
    m.epgText.visible = false
    m.epgList.visible = false
    setLogo(m.vodPoster, item.HDPosterUrl)

    lk = m.listKind
    key = ""
    if lk = "movies" then key = "m" + item.id
    if lk = "episodes" then key = "e" + item.id
    if lk = "continue" then key = nodeStr(item, "rkey")

    nl = Chr(10)
    txt = ""
    rating = nodeStr(item, "rating")
    if rating <> "" and rating <> "0" then txt = "Rating: " + rating + nl
    if lk = "episodes" then
        dur = Int(Val(nodeStr(item, "dur")))
        if dur > 0 then txt = txt + fmtDur(dur) + nl
    end if
    e = invalid
    if key <> "" then e = resumeFor(key)
    if e <> invalid then txt = txt + "Resume at " + fmtDur(e.p) + " of " + fmtDur(e.d) + nl
    plot = nodeStr(item, "plot")
    if plot <> "" then txt = txt + nl + plot + nl
    if lk = "series" then
        txt = txt + nl + "OK: open series"
    else if lk = "seasons" then
        txt = txt + nl + "OK: open season"
    else
        txt = txt + nl + "OK: details and play"
    end if
    m.vodInfo.text = txt
    m.vodInfo.visible = true
end sub

' ---------------------------------------------------------------------
' Movies: details come from get_vod_info
' ---------------------------------------------------------------------

sub openMovie(item as Object)
    m.pendingItem = item
    showStatus("Loading details ...", 0)
    runTask("vodinfo", apiUrl("get_vod_info", "&vod_id=" + urlEnc(item.id)), item.id, "onVodInfo")
end sub

sub onVodInfo(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    item = m.pendingItem
    if item = invalid then return
    if t.param <> item.id then return
    hideStatus()

    d = t.data
    if t.errorMsg <> "" or d = invalid then
        d = { name: "", plot: "", cast: "", director: "", genre: "", year: "", rating: "", dur: 0, ext: "", image: "" }
        showStatus("Could not load movie details - trying to play anyway", 3)
    end if

    ext = d.ext
    if ext = "" then ext = "mp4"
    icon = d.image
    if icon = "" and item.HDPosterUrl <> invalid then icon = item.HDPosterUrl

    meta = ""
    if d.year <> "" then meta = d.year
    if d.rating <> "" and d.rating <> "0" then meta = joinMeta(meta, "Rating " + d.rating)
    if d.dur > 0 then meta = joinMeta(meta, fmtDur(d.dur))
    if d.genre <> "" then meta = joinMeta(meta, d.genre)
    cast = ""
    if d.director <> "" then cast = "Director: " + d.director
    if d.cast <> "" then cast = joinMeta(cast, "Cast: " + d.cast)

    openDetail({ kind: "movie", key: "m" + item.id, id: item.id, title: baseTitle(item), icon: icon, ext: ext, plot: d.plot, meta: meta, cast: cast, dur: d.dur, sid: "", season: 0 })
end sub

function joinMeta(a as String, b as String) as String
    if a = "" then return b
    return a + "     " + b
end function

' ---------------------------------------------------------------------
' Series -> seasons -> episodes
' ---------------------------------------------------------------------

sub openSeries(item as Object)
    m.pendingItem = item
    showStatus("Loading series ...", 0)
    runTask("seriesinfo", apiUrl("get_series_info", "&series_id=" + urlEnc(item.id)), item.id, "onSeriesInfo")
end sub

sub onSeriesInfo(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    item = m.pendingItem
    if item = invalid then return
    if t.param <> item.id then return

    d = t.data
    if t.errorMsg <> "" or d = invalid then
        showStatus("Could not load the series: " + t.errorMsg, 5)
        return
    end if
    if d.seasons.Count() = 0 then
        showStatus("This series has no episodes listed", 4)
        return
    end if
    d.id = item.id
    if d.name = "" then d.name = baseTitle(item)
    if d.cover = "" and item.HDPosterUrl <> invalid then d.cover = item.HDPosterUrl
    m.seriesData = d

    pushNav()
    if d.seasons.Count() = 1 then
        showEpisodes(d.seasons[0])
    else
        m.listKind = "seasons"
        showChannels(seasonsNode(d), "No seasons found.")
    end if
end sub

function seasonsNode(d as Object) as Object
    items = []
    for each s in d.seasons
        label = "Season " + s.num.ToStr() + "   (" + s.eps.Count().ToStr() + " episodes)"
        if s.num = 0 then label = "Specials   (" + s.eps.Count().ToStr() + " episodes)"
        icon = s.cover
        if icon = "" then icon = d.cover
        items.push({ id: "s" + s.num.ToStr(), title: label, HDPosterUrl: icon })
    end for
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    return root
end function

sub openSeason(item as Object)
    d = m.seriesData
    if d = invalid then return
    num = Int(Val(Mid(item.id, 2)))
    for each s in d.seasons
        if s.num = num then
            pushNav()
            showEpisodes(s)
            return
        end if
    end for
end sub

sub showEpisodes(season as Object)
    d = m.seriesData
    items = []
    for each ep in season.eps
        et = ep.title
        if et = "" then et = "Episode " + ep.num.ToStr()
        img = ep.image
        if img = "" then img = d.cover
        items.push({ id: ep.id, title: "E" + two(ep.num) + "   " + et, HDPosterUrl: img, ext: ep.ext, dur: ep.dur, plot: ep.plot, season: season.num, epnum: ep.num, et: et })
    end for
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    decorateResume(root, "e")
    m.listKind = "episodes"
    showChannels(root, "No episodes found.")
end sub

function episodeDetail(ep as Object, sNum as Integer) as Object
    d = m.seriesData
    et = ep.title
    if et = "" then et = "Episode " + ep.num.ToStr()
    ext = ep.ext
    if ext = "" then ext = "mp4"
    icon = ep.image
    if icon = "" then icon = d.cover
    meta = "Season " + sNum.ToStr() + "     Episode " + ep.num.ToStr()
    if ep.dur > 0 then meta = joinMeta(meta, fmtDur(ep.dur))
    return { kind: "episode", key: "e" + ep.id, id: ep.id, title: d.name + "  -  S" + two(sNum) + "E" + two(ep.num) + "  " + et, icon: icon, ext: ext, plot: ep.plot, meta: meta, cast: "", dur: ep.dur, sid: d.id, season: sNum }
end function

sub openEpisode(item as Object)
    d = m.seriesData
    if d = invalid then return
    sNum = Int(Val(nodeStr(item, "season")))
    for each s in d.seasons
        if s.num = sNum then
            for each ep in s.eps
                if ep.id = item.id then
                    openDetail(episodeDetail(ep, sNum))
                    return
                end if
            end for
        end if
    end for
end sub

' the episode that follows ep (same season, else first of the next season)
function nextEpisode(cur as Object) as Object
    d = m.seriesData
    if d = invalid then return invalid
    if cur.kind <> "episode" or cur.sid <> d.id then return invalid
    for si = 0 to d.seasons.Count() - 1
        s = d.seasons[si]
        if s.num = cur.season then
            for i = 0 to s.eps.Count() - 1
                if s.eps[i].id = cur.id then
                    if i + 1 < s.eps.Count() then return episodeDetail(s.eps[i + 1], s.num)
                    if si + 1 < d.seasons.Count() then
                        ns = d.seasons[si + 1]
                        if ns.eps.Count() > 0 then return episodeDetail(ns.eps[0], ns.num)
                    end if
                    return invalid
                end if
            end for
        end if
    end for
    return invalid
end function

' ---------------------------------------------------------------------
' Navigation stack (series -> seasons -> episodes)
' ---------------------------------------------------------------------

sub pushNav()
    m.navStack.push({ node: m.chList.content, idx: m.chList.itemFocused, kind: m.listKind })
end sub

sub popNav()
    s = m.navStack.Pop()
    m.listKind = s.kind
    m.chList.content = s.node
    if s.idx > 0 then m.chList.jumpToItem = s.idx
    m.chList.setFocus(true)
    refreshResumeLabels()
    updateHint()
    scheduleEpg()
end sub

' ---------------------------------------------------------------------
' Detail screen: poster, text and Play / Resume / Start over
' ---------------------------------------------------------------------

sub openDetail(d as Object)
    m.detail = d
    setLogo(m.detPoster, d.icon)
    m.detTitle.text = d.title
    m.detMeta.text = d.meta
    m.detPlot.text = d.plot
    m.detCast.text = d.cast

    e = resumeFor(d.key)
    labels = []
    m.detActs = []
    if e <> invalid then
        labels.push("Resume from " + fmtDur(e.p))
        m.detActs.push("resume")
        labels.push("Start over")
        m.detActs.push("start")
    else
        labels.push("Play")
        m.detActs.push("play")
    end if
    items = []
    for each l in labels
        items.push({ title: l })
    end for
    node = CreateObject("roSGNode", "ContentNode")
    node.update({ children: items }, true)
    m.detActions.content = node
    m.detActions.jumpToItem = 0

    hideStatus()
    m.detGroup.visible = true
    m.detailOpen = true
    m.detActions.setFocus(true)
end sub

sub closeDetail()
    m.detGroup.visible = false
    m.detailOpen = false
    m.chList.setFocus(true)
    updateHint()
end sub

sub onDetAction(event as Object)
    idx = event.getData()
    if idx < 0 or idx >= m.detActs.Count() then return
    act = m.detActs[idx]
    d = m.detail
    startAt = 0
    if act = "resume" then
        e = resumeFor(d.key)
        if e <> invalid then startAt = e.p - 5
        if startAt < 0 then startAt = 0
    end if
    closeDetail()
    startVod(d, startAt)
end sub

' ---------------------------------------------------------------------
' Continue watching + resume storage
' ---------------------------------------------------------------------

function loadResume() as Object
    s = regRead("resume")
    if s = "" then return []
    arr = ParseJson(s)
    if type(arr) <> "roArray" then return []
    return arr
end function

function resumeFor(key as String) as Object
    for each e in loadResume()
        if e.k = key then return e
    end for
    return invalid
end function

function resumeMap() as Object
    map = {}
    for each e in loadResume()
        map[e.k] = e
    end for
    return map
end function

sub removeResume(key as String)
    arr = loadResume()
    out = []
    for each e in arr
        if e.k <> key then out.push(e)
    end for
    if out.Count() <> arr.Count() then regWrite("resume", FormatJson(out))
end sub

sub putResume(d as Object, posn as Integer, dur as Integer)
    icon = d.icon
    if Len(icon) > 140 then icon = ""
    e = { k: d.key, p: posn, d: dur, t: nowSecs(), n: Left(d.title, 70), i: icon, x: d.ext, id: d.id, ty: "m", sid: "", se: 0 }
    if d.kind = "episode" then
        e.ty = "e"
        e.sid = d.sid
        e.se = d.season
    end if
    out = [e]
    for each x in loadResume()
        if x.k <> d.key and out.Count() < 40 then out.push(x)
    end for
    js = FormatJson(out)
    while Len(js) > 9000 and out.Count() > 1
        out.Pop()
        js = FormatJson(out)
    end while
    regWrite("resume", js)
end sub

function continueNode() as Object
    want = "m"
    if m.mode = "series" then want = "e"
    items = []
    for each e in loadResume()
        if e.ty = want then
            items.push({ id: e.id, title: e.n + "   (resume " + fmtDur(e.p) + ")", HDPosterUrl: e.i, rkey: e.k })
        end if
    end for
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    return root
end function

sub openContinue(item as Object)
    e = resumeFor(nodeStr(item, "rkey"))
    if e = invalid then
        showStatus("That entry is no longer available", 3)
        return
    end if
    kind = "movie"
    if e.ty = "e" then kind = "episode"
    ext = e.x
    if ext = "" then ext = "mp4"
    openDetail({ kind: kind, key: e.k, id: e.id, title: e.n, icon: e.i, ext: ext, plot: "", meta: "Stopped at " + fmtDur(e.p) + " of " + fmtDur(e.d), cast: "", dur: e.d, sid: e.sid, season: e.se })
end sub

' adds "   (resume 12:34)" to the titles of items that have saved progress
sub decorateResume(node as Object, prefix as String)
    map = resumeMap()
    if map.Count() = 0 then return
    for i = 0 to node.getChildCount() - 1
        ch = node.getChild(i)
        e = map[prefix + ch.id]
        if e <> invalid then ch.title = stripResume(ch.title) + "   (resume " + fmtDur(e.p) + ")"
    end for
end sub

function stripResume(t as String) as String
    p = Instr(1, t, "   (resume ")
    if p > 0 then return Left(t, p - 1)
    return t
end function

function cloneList(node as Object) as Object
    items = []
    for i = 0 to node.getChildCount() - 1
        ch = node.getChild(i)
        it = { id: ch.id, title: ch.title, HDPosterUrl: ch.HDPosterUrl }
        for each f in ["rating", "ext", "dur", "plot", "season", "epnum", "et", "rkey"]
            if ch.hasField(f) then it[f] = ch.getField(f)
        end for
        items.push(it)
    end for
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    return root
end function

' list items are not re-drawn when a title changes, so build a fresh node
sub refreshResumeLabels()
    c = m.chList.content
    if c = invalid then return
    lk = m.listKind
    if lk <> "movies" and lk <> "episodes" and lk <> "continue" then return
    idx = m.chList.itemFocused
    if idx < 0 then idx = 0
    if lk = "continue" then
        node = continueNode()
    else
        node = cloneList(c)
        pre = "m"
        if lk = "episodes" then pre = "e"
        decorateResume(node, pre)
    end if
    m.chList.content = node
    n = node.getChildCount()
    if idx >= n then idx = n - 1
    if idx > 0 then m.chList.jumpToItem = idx
end sub

' ---------------------------------------------------------------------
' Playback
' ---------------------------------------------------------------------

sub startVod(d as Object, startAt as Integer)
    m.vod = d
    m.vodPlaying = true
    m.vodStarted = false
    seg = "movie"
    if d.kind = "episode" then seg = "series"
    url = m.server + "/" + seg + "/" + urlEnc(m.user) + "/" + urlEnc(m.pass) + "/" + d.id + "." + d.ext

    c = CreateObject("roSGNode", "ContentNode")
    c.url = url
    c.title = d.title
    fmt = vodFormat(d.ext)
    if fmt <> "" then c.streamFormat = fmt
    c.live = false
    if startAt > 0 then c.PlayStart = startAt
    m.video.content = c
    m.video.visible = true
    m.video.control = "play"
    m.video.setFocus(true)
    m.overlay.visible = false
    m.resumeTimer.control = "stop"
    m.resumeTimer.control = "start"
    if startAt > 0 then
        showStatus("Resuming at " + fmtDur(startAt) + " ...", 0)
    else
        showStatus("Starting ...", 0)
    end if
end sub

sub onVodState()
    st = m.video.state
    if st = "buffering" then
        showStatus("Buffering ...", 0)
    else if st = "playing" then
        m.vodStarted = true
        hideStatus()
    else if st = "finished" then
        onVodFinished()
    else if st = "error" then
        showStatus("Playback error: " + m.video.errorMsg + "  (Back to return)", 0)
    end if
end sub

sub onVodFinished()
    d = m.vod
    if d = invalid then
        stopPlayback()
        return
    end if
    removeResume(d.key)
    nxt = nextEpisode(d)
    if nxt <> invalid then
        showStatus("Next episode ...", 3)
        startVod(nxt, 0)
    else
        m.vodStarted = false
        stopPlayback()
        showPendingResults()
    end if
end sub

' saves, or clears, the resume point of what is playing
sub saveVodProgress()
    d = m.vod
    if d = invalid then return
    if not m.vodStarted then return
    posn = Int(m.video.position)
    dur = Int(m.video.duration)
    if dur <= 0 then dur = d.dur
    if posn < 30 then
        removeResume(d.key)
    else if dur > 0 and (posn * 100 >= dur * 95 or dur - posn < 60) then
        removeResume(d.key)
    else
        putResume(d, posn, dur)
    end if
end sub

sub onResumeTimer()
    if m.vodPlaying then saveVodProgress()
end sub
