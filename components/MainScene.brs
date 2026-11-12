' =====================================================================
' SBWatch - main scene (v0.2)
' Xtream Codes live TV client: filterable categories, channels,
' scrollable colour EPG panel, favorites, recents, stream "nerd" info.
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
    favInit()
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
    runTask("categories", apiUrl("get_live_categories", ""), "", "onCategories")
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
    m.catFilter = ""
    m.catMap = {}
    for each cc in m.allCats
        m.catMap[cc.id] = cc.title
    end for
    rebuildCats()
    m.chList.content = invalid
    m.catList.jumpToItem = 2
    m.catList.setFocus(true)
    showStatus(m.allCats.Count().ToStr() + " categories loaded", 4)
    maybeBuildIndex()
end sub

' ---------------------------------------------------------------------
' Category list + filter
' Row 0 is the filter row, then Favorites, Recently Watched, then the
' provider's categories (filtered by m.catFilter).
' ---------------------------------------------------------------------

function rebuildCats() as Integer
    items = []
    items.push({ id: "__search", title: "Search ..." })
    if m.catFilter = "" then
        items.push({ id: "__filter", title: "Filter categories ..." })
    else
        items.push({ id: "__filter", title: "Filter: " + m.catFilter + "   (OK to edit / clear)" })
    end if
    items.push({ id: "__fav", title: "Favorites" })
    items.push({ id: "__rec", title: "Recently Watched" })

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
    dlg.buttons = ["Apply", "Clear", "Cancel"]
    dlg.observeField("buttonSelected", "onFilterButton")
    m.fdlg = dlg
    m.top.dialog = dlg
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

    cnt = rebuildCats()
    if cnt > 0 then
        m.catList.jumpToItem = 4
    else
        m.catList.jumpToItem = 1
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
    idx = event.getData()
    cat = m.catList.content.getChild(idx)
    if cat = invalid then return

    if cat.id = "__filter" then
        openFilterDialog()
        return
    end if
    if cat.id = "__search" then
        openSearchDialog()
        return
    end if

    m.curCat = cat.id
    if cat.id = "__fav" then
        showChannels(nodeFromList(loadList("favs")), "No favorites yet. Press * on a channel to add one.")
    else if cat.id = "__rec" then
        showChannels(nodeFromList(loadList("recents")), "Nothing watched yet.")
    else
        showStatus("Loading channels ...", 0)
        runTask("streams", apiUrl("get_live_streams", "&category_id=" + urlEnc(cat.id)), cat.id, "onStreams")
    end if
end sub

sub onStreams(event as Object)
    t = event.getRoSGNode()
    if t.state <> "stop" then return
    if t.param <> m.curCat then return
    if t.errorMsg <> "" then
        showStatus("Could not load channels: " + t.errorMsg, 0)
        return
    end if
    showChannels(t.content, "No channels in this category.")
end sub

sub showChannels(node as Object, emptyMsg as String)
    m.chList.content = node
    n = node.getChildCount()
    if n = 0 then
        showStatus(emptyMsg, 4)
        m.catList.setFocus(true)
        return
    end if
    m.chList.jumpToItem = 0
    m.chList.setFocus(true)
    showStatus(n.ToStr() + " channels", 3)
    scheduleEpg()
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
    if m.video.visible then
        ' while watching, moving the (hidden) list selection = change channel
        idx = m.chList.itemFocused
        if idx >= 0 and idx <> m.playingIndex then playChannel(idx)
        return
    end if
    scheduleEpg()
end sub

sub onChSelected(event as Object)
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
    if m.video.visible then
        showOverlay()
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
    m.chName.text = chanName(item)
    setLogo(m.chLogo, item.HDPosterUrl)
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
    if id = m.playingId then m.ovEpg.text = ov
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

    m.playingIndex = index
    m.playingId = item.id
    m.triedTs = false
    m.ovName.text = chanName(item)
    m.ovEpg.text = ""
    m.playingIcon = ""
    if item.HDPosterUrl <> invalid then m.playingIcon = item.HDPosterUrl
    setLogo(m.ovLogo, m.playingIcon)

    e = cachedEpg(item.id)
    if e <> invalid then
        m.ovEpg.text = e.ov
    else
        requestEpg(item.id)
    end if

    addRecent(item.id, chanName(item), m.playingIcon)
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
    c.title = m.ovName.text
    if ext = "m3u8" then
        c.streamFormat = "hls"
    else
        c.streamFormat = "ts"
    end if
    c.live = true
    m.video.content = c
    m.video.visible = true
    m.video.control = "play"
end sub

sub onVideoState()
    st = m.video.state
    if st = "buffering" then
        showStatus("Buffering ...", 0)
    else if st = "playing" then
        hideStatus()
    else if st = "error" then
        if m.curExt = "m3u8" and not m.triedTs then
            m.triedTs = true
            showStatus("HLS failed, trying MPEG-TS ...", 0)
            startStream(m.playingId, "ts")
        else
            showStatus("Playback error: " + m.video.errorMsg + "  (Back to return)", 0)
            showOverlay()
        end if
    end if
end sub

sub stopPlayback()
    m.video.control = "stop"
    m.video.visible = false
    m.overlay.visible = false
    m.ovTimer.control = "stop"
    m.nerd.visible = false
    m.nerdTimer.control = "stop"
    hideStatus()
    m.chList.setFocus(true)
    scheduleEpg()
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
    m.overlay.visible = true
    m.ovTimer.control = "stop"
    m.ovTimer.control = "start"
end sub

sub onOvTimer()
    m.overlay.visible = false
end sub

' ---------------------------------------------------------------------
' Stream "nerd" info
' ---------------------------------------------------------------------

sub toggleNerd()
    if m.nerd.visible then
        m.nerd.visible = false
        m.nerdTimer.control = "stop"
    else
        updateNerd()
        m.nerd.visible = true
        m.nerdTimer.control = "start"
    end if
end sub

sub onNerdTimer()
    if m.nerd.visible then updateNerd()
end sub

function maskUrl(u as String) as String
    if m.user <> "" then u = u.Replace(m.user, "***")
    if m.pass <> "" then u = u.Replace(m.pass, "***")
    return u
end function

sub updateNerd()
    v = m.video
    lines = []
    lines.push("STREAM INFO     (Replay > Hide stream info to close)")
    lines.push("")
    lines.push("Channel:    " + m.ovName.text + "   [stream id " + m.playingId + "]")

    fmtName = "HLS (.m3u8)"
    if m.curExt = "ts" then fmtName = "MPEG-TS (.ts)"
    req = "Requested:  " + fmtName
    if m.triedTs then req = req + "   (HLS failed, fell back automatically)"
    lines.push(req)

    lines.push("State:      " + v.state + "     Position: " + Int(v.position).ToStr() + " s")

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
        lines.push("Resolution: " + res + "     Segment bitrate: " + fmtBps(ss.segBitrateBps) + "     Seg #" + toS(ss.segSequence))
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
        lines.push("Audio tracks: " + tracks.Count().ToStr() + "     Current: " + toS(fldOf(v, "currentAudioTrack")))
    end if

    if url = "" then url = v.content.url
    subs = fldOf(v, "availableSubtitleTracks")
    subTxt = "none listed by the stream"
    if type(subs) = "roArray" then
        if subs.Count() > 0 then subTxt = subs.Count().ToStr() + " track(s) listed"
    end if
    capMode = toS(fldOf(v, "globalCaptionMode"))
    if capMode = "" then capMode = "n/a"
    lines.push("Subtitles: " + subTxt + "     Roku caption mode: " + capMode)
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
    m.nerdText.text = txt
end sub

' ---------------------------------------------------------------------
' Playback menu (* while watching)
' ---------------------------------------------------------------------

sub showPlayMenu()
    nerdLbl = "Show stream info (nerd)"
    if m.nerd.visible then nerdLbl = "Hide stream info"
    favLbl = "Add to favorites"
    if isFav(m.playingId) then favLbl = "Remove from favorites"
    swLbl = "Force MPEG-TS (.ts)"
    if m.curExt = "ts" then swLbl = "Force HLS (.m3u8)"

    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = m.ovName.text
    dlg.message = ["Playback options"]
    dlg.buttons = ["Open channel guide", nerdLbl, favLbl, swLbl, "Close"]
    dlg.observeField("buttonSelected", "onPlayMenu")
    m.menuDlg = dlg
    m.top.dialog = dlg
end sub

sub onPlayMenu(event as Object)
    idx = event.getData()
    m.menuDlg.close = true
    if idx = 0 then
        openGuide()
    else if idx = 1 then
        toggleNerd()
    else if idx = 2 then
        toggleFav(m.playingId, m.ovName.text, m.playingIcon)
    else if idx = 3 then
        if m.curExt = "m3u8" then
            m.triedTs = true
            startStream(m.playingId, "ts")
        else
            startStream(m.playingId, "m3u8")
        end if
    end if
end sub

' ---------------------------------------------------------------------
' Favorites / recents (stored in the Roku registry; 32 KB app limit)
' ---------------------------------------------------------------------

function loadList(key as String) as Object
    s = regRead(key)
    if s = "" then return []
    arr = ParseJson(s)
    if arr = invalid then return []
    return arr
end function

function saveList(key as String, arr as Object) as Boolean
    s = FormatJson(arr)
    if Len(s) > 20000 then return false
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
    for each e in loadList("favs")
        if e.id = id then return true
    end for
    return false
end function

sub addRecent(id as String, title as String, icon as String)
    rec = loadList("recents")
    out = [{ id: id, title: title, icon: icon }]
    for each e in rec
        if e.id <> id and out.Count() < 25 then out.push(e)
    end for
    saveList("recents", out)
end sub

sub toggleFav(id as String, title as String, iconIn as Dynamic)
    icon = ""
    if iconIn <> invalid then icon = iconIn
    favs = loadList("favs")
    found = -1
    for i = 0 to favs.Count() - 1
        if favs[i].id = id then found = i
    end for

    if found >= 0 then
        favs.Delete(found)
        note = "Removed from favorites"
    else
        favs.push({ id: id, title: title, icon: icon })
        note = "Added to favorites"
    end if

    if not saveList("favs", favs) then
        showStatus("Favorites list is full (registry limit)", 4)
        return
    end if
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
    m.status.text = text
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
        else if key = "options" then
            item = currentFocusedItem()
            if item <> invalid then toggleFav(item.id, chanName(item), item.HDPosterUrl)
        end if
        return true
    end if

    if m.video.visible then
        if key = "back" then
            stopPlayback()
            if m.playFromGuide then
                m.playFromGuide = false
                m.gKeep = true
                openGuide()
            else
                showPendingResults()
            end if
        else if key = "up" then
            zap(-1)
        else if key = "down" then
            zap(1)
        else if key = "OK" then
            showOverlay()
        else if key = "left" then
            openGuide()
        else if key = "options" or key = "replay" then
            showPlayMenu()
        end if
        return true
    end if

    if m.favMove <> invalid then
        if key = "back" then
            endFavMove(false)
        else if key = "options" then
            endFavMove(true)
        end if
        return true
    end if

    if key = "back" then
        if m.epgList.isInFocusChain() then
            m.chList.setFocus(true)
            return true
        else if m.chList.isInFocusChain() and m.chList.content <> invalid then
            m.catList.setFocus(true)
            return true
        end if
        return false
    else if key = "options" then
        if m.chList.isInFocusChain() then
            item = currentFocusedItem()
            if item <> invalid then
                if m.curCat = "__fav" then
                    showFavMenu()
                else
                    toggleFav(item.id, chanName(item), item.HDPosterUrl)
                end if
            end if
        else
            beginLogin()
        end if
        return true
    else if key = "replay" then
        if m.catList.isInFocusChain() then
            openFilterDialog()
            return true
        else if m.chList.isInFocusChain() then
            openGuide()
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
        if m.catList.isInFocusChain() and m.chList.content <> invalid then
            if m.chList.content.getChildCount() > 0 then
                m.chList.setFocus(true)
                return true
            end if
        else if m.chList.isInFocusChain() and m.epgList.visible then
            m.epgList.setFocus(true)
            return true
        end if
    end if
    return false
end function
