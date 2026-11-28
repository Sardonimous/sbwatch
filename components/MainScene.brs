' =====================================================================
' SBWatch - main scene (v0.2)
' Xtream Codes live TV client: filterable categories, channels,
' scrollable color EPG panel, favorites, recents, stream "nerd" info.
' Channels are loaded per category (never all at once) so 30,000-channel
' providers stay within Roku memory limits.
' =====================================================================

sub init()
    m.catList = m.top.findNode("catList")
    m.chList = m.top.findNode("chList")
    m.epgText = m.top.findNode("epgText")
    m.epgList = m.top.findNode("epgList")
    m.chName = m.top.findNode("chName")
    m.video = m.top.findNode("video")
    m.overlay = m.top.findNode("overlay")
    m.ovName = m.top.findNode("ovName")
    m.ovLogo = m.top.findNode("ovLogo")
    m.ovHelp = m.top.findNode("ovHelp")
    m.okPrompt = false
    m.audioCheckTimer = m.top.findNode("audioCheckTimer")
    m.audioCheckTimer.observeField("fire", "onAudioCheck")
    m.sortBase = invalid
    m.sortCur = invalid
    m.sortIdx = -1
    m.chLogo = m.top.findNode("chLogo")
    m.playingIcon = ""
    m.ovEpg = m.top.findNode("ovEpg")
    m.nerd = m.top.findNode("nerd")
    m.nerdText = m.top.findNode("nerdText")
    m.status = m.top.findNode("status")
    m.statusBar = m.top.findNode("statusBar")
    m.playFromGuide = false
    m.epgTimer = m.top.findNode("epgTimer")
    m.ovTimer = m.top.findNode("ovTimer")
    m.statusTimer = m.top.findNode("statusTimer")
    m.nerdTimer = m.top.findNode("nerdTimer")
    m.nerdHideTimer = m.top.findNode("nerdHideTimer")
    m.nerdHideTimer.observeField("fire", "onNerdHide")
    m.prevChan = invalid
    m.playingName = ""
    m.guideAfterLoad = false
    m.pendingRecent = invalid
    m.capChan = 1

    m.catList.observeField("itemSelected", "onCatSelected")
    m.chList.observeField("itemSelected", "onChSelected")
    m.chList.observeField("itemFocused", "onChFocused")
    m.video.observeField("state", "onVideoState")
    m.epgTimer.observeField("fire", "onEpgTimer")
    m.ovTimer.observeField("fire", "onOvTimer")
    m.statusTimer.observeField("fire", "onStatusTimer")
    m.nerdTimer.observeField("fire", "onNerdTimer")

    guideInit()
    searchInit()
    vodInit()
    m.catDefaultIdx = 3
    m.catFirstIdx = 4
    favInit()
    m.global.addFields({ favIds: {}, showFavStars: true })
    refreshFavIds()
    m.hint = m.top.findNode("hint")
    m.top.observeField("focusedChild", "onFocusChange")
    updateHint()
    m.devInfo = CreateObject("roDeviceInfo")

    m.tasks = []
    m.epgQueue = []
    m.epgPending = {}
    m.epgWanted = {}
    m.epgActive = 0
    m.epgCache = {}
    m.allCats = []
    m.catFilter = ""
    m.server = ""
    m.user = ""
    m.pass = ""
    m.curCat = ""
    m.focusedId = ""
    m.playingId = ""
    m.playingIndex = 0
    m.curExt = "m3u8"
    m.triedTs = false
    m.wiz = invalid
    m.dlg = invalid
    m.fdlg = invalid
    m.menuDlg = invalid
end sub

' ---------------------------------------------------------------------
' Startup / login
' ---------------------------------------------------------------------

sub startApp()
    args = m.top.launchArgs
    if args <> invalid then
        if args.server <> invalid and args.user <> invalid and args.pass <> invalid then
            regWrite("server", normServer(args.server))
            regWrite("user", args.user)
            regWrite("pass", args.pass)
        end if
    end if

    m.server = regRead("server")
    m.user = regRead("user")
    m.pass = regRead("pass")

    if m.server = "" or m.user = "" then
        beginLogin()
    else
        verifyLogin()
    end if
end sub

sub beginLogin()
    m.wiz = { step: 0, server: m.server, user: m.user, pass: m.pass }
    askStep()
end sub

sub askStep()
    titles = ["Server URL", "Username", "Password"]
    msgs = ["Example: http://host:8080", "Your Xtream username", "Your Xtream password"]
    values = [m.wiz.server, m.wiz.user, m.wiz.pass]
    s = m.wiz.step

    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = titles[s]
    dlg.message = [msgs[s]]
    dlg.text = values[s]
    if s = 2 then
        dlg.buttons = ["Connect", "Cancel"]
    else
        dlg.buttons = ["Next", "Cancel"]
    end if
    dlg.observeField("buttonSelected", "onKbButton")
    m.dlg = dlg
    m.top.dialog = dlg
end sub

sub onKbButton(event as Object)
    if m.wiz = invalid then return
    idx = event.getData()
    txt = m.dlg.text
    if txt = invalid then txt = ""

    if idx = 1 then
        m.dlg.close = true
        m.wiz = invalid
        if m.server = "" then
            showStatus("No provider configured. Press * to set one up.", 0)
            m.top.setFocus(true)
        end if
        return
    end if

    s = m.wiz.step
    if s = 0 then
        m.wiz.server = normServer(txt)
    else if s = 1 then
        m.wiz.user = txt.Trim()
    else
        m.wiz.pass = txt.Trim()
    end if

    if s < 2 then
        m.wiz.step = s + 1
        askStep()
    else
        m.dlg.close = true
        regWrite("server", m.wiz.server)
        regWrite("user", m.wiz.user)
        regWrite("pass", m.wiz.pass)
        if m.server <> m.wiz.server or m.user <> m.wiz.user then regWrite("resume", "")
        m.server = m.wiz.server
        m.user = m.wiz.user
        m.pass = m.wiz.pass
        m.wiz = invalid
        m.epgCache = {}
        cancelSearchWork()
        verifyLogin()
    end if
end sub

sub verifyLogin()
    showStatus("Connecting to " + m.server + " ...", 0)
    runTask("auth", apiUrl("", ""), "", "onAuth")
end sub

sub onAuth(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    if t.errorMsg <> "" then
        showStatus("Connection error: " + t.errorMsg + "   (press * to change provider)", 0)
        m.top.setFocus(true)
        return
    end if
    d = t.data
    ok = false
    st = ""
    if d <> invalid then
        st = d.status
        if d.auth = 1 then ok = true
    end if
    if not ok then
        showStatus("Login rejected " + st + "   (press * to change provider)", 0)
        m.top.setFocus(true)
        return
    end if
    showStatus("Loading categories ...", 0)
    runTask("categories", apiUrl(categoriesAction(), ""), "", "onCategories")
end sub

sub onCategories(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    if t.errorMsg <> "" then
        showStatus("Could not load categories: " + t.errorMsg, 0)
        m.top.setFocus(true)
        return
    end if

    root = t.content
    m.allCats = []
    for i = 0 to root.getChildCount() - 1
        ch = root.getChild(i)
        m.allCats.push({ id: ch.id, title: ch.title })
    end for
    m.catFilter = regRead(filterKey())
    m.catMap = {}
    for each cc in m.allCats
        m.catMap[cc.id] = cc.title
    end for
    cnt = rebuildCats()
    m.chList.content = invalid
    if m.catFilter <> "" and cnt > 0 then
        m.catList.jumpToItem = m.catFirstIdx
    else
        m.catList.jumpToItem = m.catDefaultIdx
    end if
    m.catList.setFocus(true)
    if m.catFilter <> "" then
        showStatus("Filter '" + m.catFilter + "' restored: " + cnt.ToStr() + " of " + m.allCats.Count().ToStr() + " categories", 5)
    else
        showStatus(m.allCats.Count().ToStr() + " categories loaded", 4)
    end if
    maybeBuildIndex()
end sub

' ---------------------------------------------------------------------
' Category list + filter
' Row 0 is the filter row, then Favorites, Recently Watched, then the
' provider's categories (filtered by m.catFilter).
' ---------------------------------------------------------------------

function rebuildCats() as Integer
    items = []
    items.push({ id: "__mode", title: "Browse: " + modeName() + "   (OK to change)" })
    items.push({ id: "__search", title: "Search ..." })
    if m.catFilter = "" then
        items.push({ id: "__filter", title: "Filter categories ..." })
    else
        items.push({ id: "__filter", title: "Filter: " + m.catFilter + "   (OK to edit / clear)" })
    end if
    items.push({ id: "__fav", title: "Favorites" })
    if m.mode = "live" then
        items.push({ id: "__rec", title: "Recently Watched" })
    else
        items.push({ id: "__cont", title: "Continue Watching" })
    end if
    m.catDefaultIdx = 3
    m.catFirstIdx = items.Count()

    words = []
    if m.catFilter <> "" then
        tk = m.catFilter.Tokenize(" ")
        for each w in tk
            words.push(w)
        end for
    end if

    cnt = 0
    for each c in m.allCats
        low = LCase(c.title)
        good = true
        for each w in words
            if Instr(1, low, w) = 0 then good = false
        end for
        if good then
            items.push(c)
            cnt = cnt + 1
        end if
    end for

    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    m.catList.content = root
    return cnt
end function

sub openFilterDialog()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Filter categories"
    dlg.message = ["Words match anywhere in the name. Example: us sports"]
    dlg.text = m.catFilter
    setVoiceGeneric(dlg, "filter")
    dlg.buttons = ["Apply", "Clear", "Cancel"]
    dlg.observeField("buttonSelected", "onFilterButton")
    m.fdlg = dlg
    m.top.dialog = dlg
    setVoiceGeneric(dlg, "filter, shown")
end sub

sub onFilterButton(event as Object)
    idx = event.getData()
    txt = m.fdlg.text
    if txt = invalid then txt = ""
    m.fdlg.close = true

    if idx = 2 then return
    if idx = 1 then
        m.catFilter = ""
    else
        m.catFilter = LCase(txt.Trim())
    end if

    regWrite(filterKey(), m.catFilter)
    cnt = rebuildCats()
    if cnt > 0 then
        m.catList.jumpToItem = m.catFirstIdx
    else
        m.catList.jumpToItem = 2
    end if
    m.catList.setFocus(true)
    if m.catFilter = "" then
        showStatus("Filter cleared: " + m.allCats.Count().ToStr() + " categories", 3)
    else
        showStatus(cnt.ToStr() + " of " + m.allCats.Count().ToStr() + " categories match", 4)
    end if
end sub

' ---------------------------------------------------------------------
' Categories and channels
' ---------------------------------------------------------------------

sub onCatSelected(event as Object)
    selectCategory(event.getData(), false)
end sub

' OK on a category row. wantGuide (Live TV only) opens the full guide once the list is showing.
sub selectCategory(idx as Integer, wantGuide as Boolean)
    cat = m.catList.content.getChild(idx)
    if cat = invalid then return

    if cat.id = "__filter" then
        if not wantGuide then openFilterDialog()
        return
    end if
    if cat.id = "__search" then
        if not wantGuide then openSearchDialog()
        return
    end if
    if cat.id = "__mode" then
        if not wantGuide then openModeMenu()
        return
    end if

    m.guideAfterLoad = wantGuide
    m.curCat = cat.id
    m.navStack = []
    if m.mode <> "live" then
        vodCatSelected(cat)
        return
    end if
    m.listKind = "channels"
    if cat.id = "__fav" then
        showChannels(nodeFromList(loadList(favKey())), "No favorites yet. Press * on a channel to add one.")
    else if cat.id = "__rec" then
        showChannels(nodeFromList(loadList("recents")), "Nothing watched yet.")
    else
        showStatus("Loading channels ...", 0)
        runTask("streams", apiUrl("get_live_streams", "&category_id=" + urlEnc(cat.id)), cat.id, "onStreams")
    end if
end sub

' Right (and Replay on Live TV = full guide) on a category: the same as OK, except that a list
' that is already showing this category is kept instead of being fetched again.
sub openFocusedCategory(wantGuide as Boolean)
    c0 = m.catList.content
    if c0 = invalid then return
    idx = m.catList.itemFocused
    cat = c0.getChild(idx)
    if cat = invalid then return
    if cat.id = "__filter" or cat.id = "__search" or cat.id = "__mode" then return

    c = m.chList.content
    keep = false
    if c <> invalid and cat.id = m.curCat then
        ' Favorites / Recently Watched / Continue Watching can change, so they are always rebuilt
        if cat.id <> "__fav" and cat.id <> "__rec" and cat.id <> "__cont" then
            if c.getChildCount() > 0 then keep = true
        end if
    end if

    if keep then
        m.chList.setFocus(true)
        scheduleEpg()
        if wantGuide and m.mode = "live" then openGuide()
    else
        selectCategory(idx, wantGuide)
    end if
end sub

sub onStreams(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    if t.param <> m.curCat then return
    if t.errorMsg <> "" then
        m.guideAfterLoad = false
        showStatus("Could not load the list: " + t.errorMsg, 0)
        return
    end if
    node = t.content
    if m.listKind = "movies" then decorateResume(node, "m")
    showChannels(node, "Nothing in this category.")
end sub

sub showChannels(node as Object, emptyMsg as String)
    wantGuide = m.guideAfterLoad
    m.guideAfterLoad = false
    showStars = false
    if m.curCat <> "__fav" then
        slk = m.listKind
        if m.mode = "live" or slk = "movies" or slk = "series" then showStars = true
    end if
    m.global.showFavStars = showStars
    m.chList.content = node
    updateHint()
    n = node.getChildCount()
    if n = 0 then
        showStatus(emptyMsg, 4)
        m.catList.setFocus(true)
        return
    end if
    m.chList.jumpToItem = 0
    m.chList.setFocus(true)
    showStatus(n.ToStr() + " " + listNoun(), 3)
    scheduleEpg()
    if wantGuide and m.mode = "live" then openGuide()
end sub

function currentFocusedItem() as Object
    c = m.chList.content
    if c = invalid then return invalid
    idx = m.chList.itemFocused
    if idx < 0 or idx >= c.getChildCount() then return invalid
    return c.getChild(idx)
end function

sub onChFocused()
    if m.guideOpen then
        drawGuide()
        return
    end if
    if m.favMove <> invalid then
        favMoveFocused()
        return
    end if
    if m.vodPlaying then
        vodListFocused()
        return
    end if
    if m.video.visible then
        ' while watching, moving the (hidden) list selection = change channel
        idx = m.chList.itemFocused
        if idx >= 0 and idx <> m.playingIndex then playChannel(idx)
        return
    end if
    scheduleEpg()
end sub

sub onChSelected(event as Object)
    if m.nextPending <> invalid then
        playNextNow()
        return
    end if
    if m.guideOpen then
        idx = event.getData()
        closeGuide()
        if m.video.visible and idx = m.playingIndex then return
        m.playFromGuide = true
        playChannel(idx)
        return
    end if
    if m.favMove <> invalid then
        endFavMove(true)
        return
    end if
    if m.vodPlaying or m.video.visible then
        playerOk()
        return
    end if
    if m.mode <> "live" then
        vodSelected(event.getData())
        return
    end if
    m.playFromGuide = false
    playChannel(event.getData())
end sub

' ---------------------------------------------------------------------
' EPG (Xtream get_short_epg, fetched lazily for the focused channel)
' ---------------------------------------------------------------------

sub scheduleEpg()
    m.epgTimer.control = "stop"
    m.epgTimer.control = "start"
end sub

sub onEpgTimer()
    item = currentFocusedItem()
    if item = invalid then return
    m.focusedId = item.id
    setRtl(m.chName, chanName(item), "font:MediumBoldSystemFont", 28, 0)
    setLogo(m.chLogo, item.HDPosterUrl)
    if m.mode <> "live" then
        updateVodPanel(item)
        return
    end if
    m.vodPoster.visible = false
    m.vodInfo.visible = false
    m.epgWanted = {}
    m.epgWanted[item.id] = true
    if m.playingId <> "" then m.epgWanted[m.playingId] = true
    e = cachedEpg(item.id)
    if e <> invalid then
        applyEpg(e)
    else
        setEpgMessage("Loading guide ...")
        requestEpg(item.id)
    end if
end sub

function cachedEpg(id as String) as Object
    if m.epgCache.DoesExist(id) then
        e = m.epgCache[id]
        if e.exp > nowSecs() then return e
    end if
    return invalid
end function

sub requestEpg(id as String)
    m.epgWanted[id] = true
    if m.epgPending.DoesExist(id) then return
    m.epgPending[id] = true
    m.epgQueue.push(id)
    pumpEpg()
end sub

' At most 4 guide requests in flight; newest request first (LIFO) so rows
' you scroll to are served before rows you scrolled past.
sub pumpEpg()
    while m.epgActive < 4 and m.epgQueue.Count() > 0
        id = m.epgQueue.Pop()
        if m.epgWanted.DoesExist(id) or m.esIds.DoesExist(id) then
            m.epgActive = m.epgActive + 1
            runTask("epg", apiUrl("get_short_epg", "&stream_id=" + urlEnc(id) + "&limit=12"), id, "onEpg")
        else
            m.epgPending.Delete(id)
        end if
    end while
end sub

sub onEpg(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    id = t.param
    if m.epgActive > 0 then m.epgActive = m.epgActive - 1
    if m.epgPending.DoesExist(id) then m.epgPending.Delete(id)
    handleEpg(t, id)
    esTick(id)
    pumpEpg()
end sub

sub handleEpg(t as Object, id as String)
    now = nowSecs()
    if m.epgCache.Count() > 800 then m.epgCache = {}

    good = false
    if t.errorMsg = "" and t.data <> invalid then
        if t.data.listings <> invalid then good = true
    end if
    if not good then
        m.epgCache[id] = { listings: [], ov: "", exp: now + 30 }
        if id = m.focusedId and not m.guideOpen then setEpgMessage("Guide unavailable")
        if m.guideOpen then drawGuide()
        return
    end if

    items = buildEpgItems(t.data.listings)
    ov = ""
    for each it in items
        if it.kind = "NOW" then
            ov = "Now: " + it.title + "  (" + it.timeText + ")"
        else if it.kind = "NEXT" then
            if ov <> "" then ov = ov + Chr(10)
            ov = ov + "Next: " + it.title + "  (" + it.timeText + ")"
        end if
    end for

    entry = { listings: t.data.listings, ov: ov, exp: now + 300 }
    m.epgCache[id] = entry

    if id = m.focusedId and not m.guideOpen then applyEpg(entry)
    if id = m.playingId then setRtl(m.ovEpg, ov, "font:MediumSystemFont", 28, 0)
    if m.guideOpen then drawGuide()
end sub

function buildEpgItems(listings as Object) as Object
    now = nowSecs()
    items = []
    seenNext = false
    for each l in listings
        if l.stop > now then
            kind = "LATER"
            prog = 0.0
            if l.start <= now then
                kind = "NOW"
                span = l.stop - l.start
                if span > 0 then prog = (now - l.start) / span
            else if not seenNext then
                kind = "NEXT"
                seenNext = true
            end if
            d = l.desc
            if Len(d) > 260 then d = Left(d, 257) + "..."
            items.push({
                title: l.title
                desc: d
                timeText: fmtTime(l.start) + " - " + fmtTime(l.stop)
                kind: kind
                progress: prog
            })
        end if
    end for
    return items
end function

sub applyEpg(entry as Object)
    items = buildEpgItems(entry.listings)
    if items.Count() = 0 then
        setEpgMessage("No guide data for this channel")
        return
    end if
    root = CreateObject("roSGNode", "ContentNode")
    root.update({ children: items }, true)
    m.epgList.content = root
    if not m.epgList.isInFocusChain() then m.epgList.jumpToItem = 0
    m.epgText.visible = false
    m.epgList.visible = true
end sub

sub setEpgMessage(text as String)
    m.epgText.text = text
    m.epgText.visible = true
    m.epgList.visible = false
end sub

' ---------------------------------------------------------------------
' Playback
' ---------------------------------------------------------------------

sub playChannel(index as Integer)
    c = m.chList.content
    if c = invalid then return
    if index < 0 or index >= c.getChildCount() then return
    item = c.getChild(index)

    rememberPrev(item.id)
    m.playingIndex = index
    m.playingId = item.id
    m.triedTs = false
    m.playingName = chanName(item)
    setRtl(m.ovName, m.playingName, "font:LargeBoldSystemFont", 36, 0)
    setRtl(m.ovEpg, "", "font:MediumSystemFont", 28, 0)
    m.playingIcon = ""
    if item.HDPosterUrl <> invalid then m.playingIcon = item.HDPosterUrl
    setLogo(m.ovLogo, m.playingIcon)

    e = cachedEpg(item.id)
    if e <> invalid then
        setRtl(m.ovEpg, e.ov, "font:MediumSystemFont", 28, 0)
    else
        requestEpg(item.id)
    end if

    m.pendingRecent = { id: item.id, title: chanName(item), icon: m.playingIcon }
    startStream(item.id, "m3u8")
    showOverlay()
    ' keep focus on the (hidden) channel list: Up/Down then arrive as
    ' selection changes, and Back/*/Replay bubble up to onKeyEvent.
    m.chList.setFocus(true)
end sub

sub startStream(id as String, ext as String)
    m.curExt = ext
    url = m.server + "/live/" + urlEnc(m.user) + "/" + urlEnc(m.pass) + "/" + id + "." + ext
    c = CreateObject("roSGNode", "ContentNode")
    c.url = url
    c.title = nodeTitle(m.playingName)
    if ext = "m3u8" then
        c.streamFormat = "hls"
    else
        c.streamFormat = "ts"
    end if
    logLine("play live: " + maskUrl(url) + "  (" + ext + ")")
    c.live = true
    ' Roku shows in-band EIA-608 captions only when the channel is declared
    ' (a decoder such as ExoPlayer finds them by itself): CC1..CC4
    tracks = []
    for n = 1 to 4
        tracks.push({ Language: "eng", TrackName: "eia608/" + n.ToStr(), Description: "CC" + n.ToStr() })
    end for
    c.SubtitleTracks = tracks
    c.SubtitleConfig = { TrackName: "eia608/" + m.capChan.ToStr() }
    m.video.content = c
    m.video.visible = true
    m.video.control = "play"
end sub

sub onVideoState()
    logLine("video state: " + m.video.state)
    if not m.vodPlaying and not m.video.visible then return
    if m.vodPlaying then
        onVodState()
        return
    end if
    st = m.video.state
    if st = "buffering" then
        showStatus("Buffering ...", 0)
    else if st = "playing" then
        hideStatus()
        flushRecent()
    else if st = "error" then
        logVideoError("live " + m.curExt)
        if m.curExt = "m3u8" and not m.triedTs then
            m.triedTs = true
            showStatus("HLS failed, trying MPEG-TS ...", 0)
            startStream(m.playingId, "ts")
        else
            showStatus(playbackErrorText() + "   (Back to return)", 0)
            showOverlay()
        end if
    end if
end sub

sub stopPlayback()
    cancelNext()
    m.pendingRecent = invalid
    wasVod = m.vodPlaying
    if wasVod then
        saveVodProgress()
        m.vodPlaying = false
        m.resumeTimer.control = "stop"
    end if
    m.video.control = "stop"
    m.video.visible = false
    m.overlay.visible = false
    m.ovTimer.control = "stop"
    m.nerd.visible = false
    m.nerdTimer.control = "stop"
    m.nerdHideTimer.control = "stop"
    hideStatus()
    m.chList.setFocus(true)
    scheduleEpg()
    updateHint()
    if wasVod then refreshResumeLabels()
end sub

sub zap(delta as Integer)
    c = m.chList.content
    if c = invalid then return
    n = c.getChildCount()
    if n = 0 then return
    idx = m.playingIndex + delta
    if idx < 0 then idx = n - 1
    if idx >= n then idx = 0
    playChannel(idx)
    m.chList.jumpToItem = idx
end sub

sub showOverlay()
    m.ovHelp.visible = false
    m.okPrompt = false
    showOverlayFor(5)
end sub

sub showOverlayFor(secs as Integer)
    m.overlay.visible = true
    m.ovTimer.duration = secs
    m.ovTimer.control = "stop"
    m.ovTimer.control = "start"
end sub

sub onOvTimer()
    m.overlay.visible = false
    m.ovHelp.visible = false
    m.okPrompt = false
end sub

' ---------------------------------------------------------------------
' Stream "nerd" info
' ---------------------------------------------------------------------

sub toggleNerd()
    if m.nerd.visible then
        m.nerd.visible = false
        m.nerdTimer.control = "stop"
        m.nerdHideTimer.control = "stop"
    else
        updateNerd()
        m.nerd.visible = true
        m.nerdTimer.control = "start"
        m.nerdHideTimer.control = "stop"
        m.nerdHideTimer.control = "start"
    end if
end sub

sub onNerdHide()
    m.nerd.visible = false
    m.nerdTimer.control = "stop"
end sub

sub onNerdTimer()
    if m.nerd.visible then updateNerd()
    if m.overlay.visible and m.vodPlaying then updateVodBanner()
    if not m.nerd.visible and not m.overlay.visible then m.nerdTimer.control = "stop"
end sub

function maskUrl(u as String) as String
    if m.user <> "" then u = u.Replace(m.user, "***")
    if m.pass <> "" then u = u.Replace(m.pass, "***")
    return u
end function

sub updateNerd()
    v = m.video
    lines = []
    lines.push("STREAM INFO     (hides after 15 seconds)")
    lines.push("")
    if m.vodPlaying then
        lines.push("Playing:    " + m.vod.title)
        lines.push("Position:   " + fmtDur(Int(v.position)) + " / " + fmtDur(Int(v.duration)) + "     State: " + v.state + "     Left / Right: seek 10 s     Rewind / Fast-forward: 60 s")
        lines.push("Source:     " + UCase(m.vod.ext) + " file")
        if toS(m.vod.vinfo) <> "" or toS(m.vod.ainfo) <> "" then lines.push("Provider data:  video " + toS(m.vod.vinfo) + "     audio " + toS(m.vod.ainfo))
        pw = audioWarn(toS(m.vod.ainfo))
        if pw <> "" then lines.push("WARNING: " + pw)
    else
        lines.push("Channel:    " + m.playingName + "   [stream id " + m.playingId + "]")
        fmtName = "HLS (.m3u8)"
        if m.curExt = "ts" then fmtName = "MPEG-TS (.ts)"
        req = "Requested:  " + fmtName
        if m.triedTs then req = req + "   (HLS failed, fell back automatically)"
        lines.push(req)
        lines.push("State:      " + v.state + "     Position: " + Int(v.position).ToStr() + " s")
    end if

    vf = toS(fldOf(v, "videoFormat"))
    af = toS(fldOf(v, "audioFormat"))
    if vf = "" then vf = "n/a"
    if af = "" then af = "n/a"
    lines.push("Video codec: " + vf + "     Audio codec: " + af)

    ss = fldOf(v, "streamingSegment")
    if type(ss) = "roAssociativeArray" then
        w = toS(ss.width)
        h = toS(ss.height)
        res = "n/a"
        if w <> "" and w <> "0" then res = w + " x " + h
        lines.push("Resolution: " + res + "     Segment #" + toS(ss.segSequence))
    end if

    si = fldOf(v, "streamInfo")
    url = ""
    if type(si) = "roAssociativeArray" then
        lines.push("Stream bitrate: " + fmtBps(si.streamBitrate) + "     Measured throughput: " + fmtBps(si.measuredBitrate))
        under = "no"
        if si.isUnderrun = true then under = "YES"
        lines.push("Buffer underrun: " + under)
        url = toS(si.streamUrl)
    end if

    tracks = fldOf(v, "availableAudioTracks")
    if type(tracks) = "roArray" then
        lines.push("Audio tracks: " + tracks.Count().ToStr() + "     Current: " + toS(fldOf(v, "currentAudioTrack")) + "     (Playback options > Audio track switches)")
        for i = 0 to tracks.Count() - 1
            if i < 6 and type(tracks[i]) = "roAssociativeArray" then lines.push("   " + dumpAA(tracks[i]))
        end for
    end if

    if url = "" then url = v.content.url
    subs = fldOf(v, "availableSubtitleTracks")
    subTxt = "none listed by the stream"
    if type(subs) = "roArray" then
        if subs.Count() > 0 then subTxt = subs.Count().ToStr() + " track(s) listed"
    end if
    capMode = toS(fldOf(v, "globalCaptionMode"))
    if capMode = "" then capMode = "n/a"
    lines.push("Subtitles: " + subTxt + "     Roku caption mode: " + capMode + "     Requested: eia608/" + m.capChan.ToStr())
    lines.push("Display mode: " + m.devInfo.GetVideoMode())
    lines.push("")
    lines.push("URL: " + maskUrl(url))

    lines.push("")
    lines.push("RAW (what the player reports; empty/0 = not available for this stream)")
    if type(ss) = "roAssociativeArray" then lines.push("streamingSegment:  " + maskUrl(dumpAA(ss)))
    if type(si) = "roAssociativeArray" then lines.push("streamInfo:  " + maskUrl(dumpAA(si)))
    ds = fldOf(v, "downloadedSegment")
    if type(ds) = "roAssociativeArray" then lines.push("downloadedSegment:  " + maskUrl(dumpAA(ds)))

    txt = ""
    for each ln in lines
        txt = txt + ln + Chr(10)
    end for
    setRtl(m.nerdText, txt, "font:SmallSystemFont", 24, 0)
end sub

' ---------------------------------------------------------------------
' Playback menu (* while watching)
' ---------------------------------------------------------------------



' B button: captions on / off (Roku's caption mode, as Roku asks apps to do)
sub toggleCaptions()
    mode = toS(fldOf(m.video, "globalCaptionMode"))
    if mode = "" or mode = "Off" then
        setCaptions(true)
    else
        setCaptions(false)
    end if
end sub

sub setCaptions(on as Boolean)
    if on then
        if m.video.hasField("globalCaptionMode") then m.video.globalCaptionMode = "On"
        if m.video.hasField("subtitleTrack") and not m.vodPlaying then m.video.subtitleTrack = "eia608/" + m.capChan.ToStr()
        if m.vodPlaying then
            showStatus("Captions on", 3)
        else
            showStatus("Captions on (CC" + m.capChan.ToStr() + ")", 3)
        end if
    else
        if m.video.hasField("globalCaptionMode") then m.video.globalCaptionMode = "Off"
        showStatus("Captions off", 3)
    end if
end sub

' Replay menu: cycle the caption channel CC1 -> CC2 -> CC3 -> CC4 -> CC1
sub cycleCaptionChannel()
    m.capChan = m.capChan + 1
    if m.capChan > 4 then m.capChan = 1
    if m.video.hasField("subtitleTrack") then m.video.subtitleTrack = "eia608/" + m.capChan.ToStr()
    mode = toS(fldOf(m.video, "globalCaptionMode"))
    state = "on"
    if mode = "" or mode = "Off" then state = "off - press B to turn them on"
    showStatus("Caption channel CC" + m.capChan.ToStr() + "  (captions are " + state + ")", 4)
end sub

' ---------------------------------------------------------------------
' Favorites / recents (stored in the Roku registry; 32 KB app limit)
' ---------------------------------------------------------------------

function loadList(key as String) as Object
    s = regRead(key)
    if s = "" then return []
    arr = ParseJson(s)
    if type(arr) <> "roArray" then return []
    out = []
    for each e in arr
        if type(e) = "roAssociativeArray" then
            if e.i <> invalid then
                out.push({ id: toS(e.i), title: toS(e.t), icon: toS(e.c) })
            else
                out.push(e)
            end if
        end if
    end for
    return out
end function

function saveList(key as String, arr as Object) as Boolean
    ' short key names (i / t / c) keep each entry small; loadList reads both forms
    packed = []
    for each e in arr
        p = { i: e.id, t: e.title }
        ic = e.icon
        if ic <> invalid then
            if ic <> "" then p.c = ic
        end if
        packed.push(p)
    end for
    s = FormatJson(packed)
    lim = 5200
    if key = "favs" then lim = 11000
    if key = "recents" then lim = 3200
    if Len(s) > lim then return false
    regWrite(key, s)
    return true
end function

function nodeFromList(arr as Object) as Object
    root = CreateObject("roSGNode", "ContentNode")
    items = []
    for each e in arr
        ic = e.icon
        if ic = invalid then ic = ""
        items.push({ id: e.id, title: e.title, HDPosterUrl: ic })
    end for
    root.update({ children: items }, true)
    return root
end function

function isFav(id as String) as Boolean
    for each e in loadList(favKey())
        if e.id = id then return true
    end for
    return false
end function

sub addRecent(id as String, title as String, icon as String)
    rec = loadList("recents")
    out = [{ id: id, title: title, icon: icon }]
    for each e in rec
        if e.id <> id and out.Count() < 20 then out.push(e)
    end for
    saveList("recents", out)
end sub

sub toggleFav(id as String, title as String, iconIn as Dynamic)
    icon = ""
    if iconIn <> invalid then icon = iconIn
    favs = loadList(favKey())
    found = -1
    for i = 0 to favs.Count() - 1
        if favs[i].id = id then found = i
    end for

    if found >= 0 then
        m.lastFavRemoved = { k: favKey(), id: id, idx: found, t: nowSecs() }
        favs.Delete(found)
        note = "Removed from favorites"
    else
        if favs.Count() >= favCap() then
            showStatus("Favorites list is full (maximum " + favCap().ToStr() + ") - remove one first", 4)
            return
        end if
        favs.push({ id: id, title: title, icon: icon })
        note = "Added to favorites"
        ' re-adding what was just removed puts it back where it was
        rm = m.lastFavRemoved
        if rm <> invalid then
            if rm.k = favKey() and rm.id = id and nowSecs() - rm.t < 600 then
                last = favs.Count() - 1
                at = rm.idx
                if at > last then at = last
                favs = favReorderArray(favs, last, at)
                m.lastFavRemoved = invalid
            end if
        end if
    end if

    if not saveList(favKey(), favs) then
        showStatus("Favorites list is full (registry limit)", 4)
        return
    end if
    refreshFavIds()
    showStatus(note, 3)

    if m.curCat = "__fav" and not m.video.visible then
        idx = m.chList.itemFocused
        if idx >= favs.Count() then idx = favs.Count() - 1
        if idx < 0 then idx = 0
        m.chList.content = nodeFromList(favs)
        m.chList.jumpToItem = idx
    end if
    if m.guideOpen then drawGuide()
end sub

' ---------------------------------------------------------------------
' Helpers
' ---------------------------------------------------------------------

function apiUrl(action as String, extra as String) as String
    u = m.server + "/player_api.php?username=" + urlEnc(m.user) + "&password=" + urlEnc(m.pass)
    if action <> "" then u = u + "&action=" + action
    return u + extra
end function

sub runTask(kind as String, url as String, param as String, handler as String)
    t = CreateObject("roSGNode", "ApiTask")
    t.kind = kind
    t.url = url
    t.param = param
    t.observeField("state", handler)
    if m.tasks.Count() > 30 then m.tasks.Shift()
    m.tasks.push(t)
    t.control = "RUN"
end sub

sub showStatus(text as String, seconds as Integer)
    if looksLikeError(text) then logLine("STATUS: " + text)
    setRtl(m.status, text, "font:MediumSystemFont", 28, 0)
    y = 930
    if m.video.visible and not m.guideOpen then y = 745
    m.statusBar.translation = [0, y]
    m.statusBar.visible = true
    m.statusTimer.control = "stop"
    if seconds > 0 then
        m.statusTimer.duration = seconds
        m.statusTimer.control = "start"
    end if
end sub

sub hideStatus()
    m.statusBar.visible = false
    m.statusTimer.control = "stop"
end sub

sub onStatusTimer()
    m.statusBar.visible = false
end sub

' ---------------------------------------------------------------------
' Remote control
' ---------------------------------------------------------------------

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    lk = LCase(key)
    if lk = "a" or lk = "b" then key = lk
    if not isKnownKey(key) then print "SBWatch: unhandled key name: "; key

    if m.detailOpen then
        if key = "back" then closeDetail()
        return true
    end if

    if m.nextPending <> invalid then
        if key = "back" then
            stopPlayback()
            showPendingResults()
        else if key = "play" then
            playNextNow()
        end if
        return true
    end if

    if m.guideOpen then
        if key = "back" then
            closeGuide()
            showPendingResults()
        else if key = "left" then
            guideMove(-1)
        else if key = "right" then
            guideMove(1)
        else if key = "rewind" then
            guidePage(-1)
        else if key = "fastforward" then
            guidePage(1)
        else if key = "replay" then
            guideNow()
        else if key = "options" or key = "a" then
            item = currentFocusedItem()
            if item <> invalid then toggleFav(item.id, chanName(item), item.HDPosterUrl)
        end if
        return true
    end if

    if m.vodPlaying or m.video.visible then
        playerKey(key)
        return true
    end if

    if m.favMove <> invalid then
        if key = "back" then
            endFavMove(false)
        else if key = "options" or key = "a" then
            endFavMove(true)
        end if
        return true
    end if

    if key = "back" then
        if m.epgList.isInFocusChain() then
            m.chList.setFocus(true)
            return true
        else if m.chList.isInFocusChain() and m.chList.content <> invalid then
            if m.navStack.Count() > 0 then
                popNav()
            else
                m.catList.setFocus(true)
            end if
            return true
        end if
        return false
    else if key = "options" or key = "a" then
        if m.chList.isInFocusChain() then
            if key = "a" then
                toggleFavFocused()
            else if m.curCat = "__fav" then
                showFavMenu()
            else if m.curCat = "__rec" or m.curCat = "__cont" then
                showItemMenu()
            else
                toggleFavFocused()
            end if
        else if m.catList.isInFocusChain() then
            if key = "a" then
                searchFocusedCategory()
            else
                beginLogin()
            end if
        end if
        return true
    else if key = "b" then
        if m.chList.isInFocusChain() then
            cycleSort()
            return true
        end if
    else if key = "replay" then
        if m.catList.isInFocusChain() then
            if m.mode = "live" then openFocusedCategory(true)
            return true
        else if m.chList.isInFocusChain() then
            if m.mode = "live" then openGuide()
            return true
        end if
    else if key = "left" then
        if m.epgList.isInFocusChain() then
            m.chList.setFocus(true)
            return true
        else if m.chList.isInFocusChain() then
            m.catList.setFocus(true)
            return true
        end if
    else if key = "right" then
        if m.catList.isInFocusChain() then
            openFocusedCategory(false)
            return true
        else if m.chList.isInFocusChain() and m.epgList.visible then
            m.epgList.setFocus(true)
            return true
        end if
    end if
    return false
end function

' ---------------------------------------------------------------------
' Context-sensitive help line at the bottom of the main screen
' ---------------------------------------------------------------------

sub onFocusChange()
    updateHint()
end sub

sub updateHint()
    if m.hint = invalid then return
    txt = ""
    if m.favMove <> invalid then
        txt = "MOVING CHANNEL     Up / Down: reposition     OK: drop here     Back: cancel"
    else if m.epgList.isInFocusChain() then
        txt = "PROGRAM GUIDE     Up / Down: scroll programs     Left or Back: return to the channel list"
    else if m.chList.isInFocusChain() then
        lk = m.listKind
        if m.curCat = "__rec" then
            txt = "RECENTLY WATCHED     OK: play     *: remove item / clear list     A: favorite"
        else if m.curCat = "__cont" then
            txt = "CONTINUE WATCHING     OK: resume or start over     *: remove item / clear list     A: favorite"
        else if m.curCat = "__fav" and m.mode <> "live" then
            txt = "FAVORITES     OK: open / play     *: move / remove favorite     A: remove favorite"
        else if m.mode = "live" then
            if m.curCat = "__fav" then
                txt = "FAVORITES     OK: play     *: move / remove favorite     Replay: full guide"
            else
                txt = "CHANNELS     OK: play     *: add / remove favorite     Replay: full guide"
            end if
        else if lk = "series" then
            txt = "SERIES     OK: open series     A: add / remove favorite"
        else if lk = "seasons" then
            txt = "SEASONS     OK: open season     Back: back to the series list"
        else if lk = "episodes" then
            txt = "EPISODES     OK: details and play     Back: back to the seasons"
        else
            txt = "MOVIES     OK: details and play     A: add / remove favorite"
        end if
        if lk <> "seasons" and lk <> "episodes" and txt <> "" then txt = txt + "     B: sort"
    else if m.catList.isInFocusChain() then
        if m.mode = "live" then
            txt = "CATEGORIES     OK or Right: open     A: search in it     Replay: full guide     *: change provider     Back: exit"
        else
            txt = "CATEGORIES     OK or Right: open     A: search in it     *: change provider     Back: exit"
        end if
    end if
    if txt <> "" then m.hint.text = txt
end sub

' ---------------------------------------------------------------------
' Previous channel ("B" button) and direct play by id
' ---------------------------------------------------------------------

sub rememberPrev(newId as String)
    if m.playingId <> "" and m.playingId <> newId then
        m.prevChan = { id: m.playingId, name: m.playingName, icon: m.playingIcon }
    end if
end sub

sub previousChannel()
    p = m.prevChan
    if p = invalid then
        showStatus("No previous channel yet", 2)
        return
    end if
    playDirect(p.id, p.name, p.icon)
end sub

sub playDirect(id as String, name as String, icon as String)
    rememberPrev(id)
    m.playingIndex = -1
    m.playingId = id
    m.triedTs = false
    m.playingName = name
    setRtl(m.ovName, name, "font:LargeBoldSystemFont", 36, 0)
    setRtl(m.ovEpg, "", "font:MediumSystemFont", 28, 0)
    m.playingIcon = icon
    setLogo(m.ovLogo, icon)

    e = cachedEpg(id)
    if e <> invalid then
        setRtl(m.ovEpg, e.ov, "font:MediumSystemFont", 28, 0)
    else
        requestEpg(id)
    end if

    m.pendingRecent = { id: id, title: name, icon: icon }
    startStream(id, "m3u8")
    showOverlay()

    ' keep the channel list selection in step when the channel is in it
    c = m.chList.content
    if c <> invalid then
        for i = 0 to c.getChildCount() - 1
            if c.getChild(i).id = id then
                m.playingIndex = i
                m.chList.jumpToItem = i
                exit for
            end if
        end for
    end if
end sub

function isKnownKey(key as String) as Boolean
    known = ["back", "up", "down", "left", "right", "OK", "options", "replay", "rewind", "fastforward", "play", "info", "a", "b"]
    for each k in known
        if key = k then return true
    end for
    return false
end function

' a channel joins Recently Watched once it has really started playing
sub flushRecent()
    p = m.pendingRecent
    if p = invalid then return
    m.pendingRecent = invalid
    addRecent(p.id, p.title, p.icon)
end sub
