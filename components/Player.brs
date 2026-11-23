' =====================================================================
' Player controls shared by Live TV, Movies and Series
'   OK          first press: info screen, second press: playback options
'   Play/Pause  pause / resume          A  favorite          B  captions
'   Back        stop                    *  playback options
'   Live:  Up/Down channel, Left channel guide
'   VOD:   Left/Right seek 10 s, Rewind/Fast-forward 60 s, Replay back 10 s,
'          Up/Down previous / next episode (episode lists)
' Remote focus stays on the hidden channel list so that OK reaches the app.
' =====================================================================

sub playerKey(key as String)
    if key = "back" then
        wasVod = m.vodPlaying
        stopPlayback()
        if wasVod then
            showPendingResults()
        else if m.playFromGuide then
            m.playFromGuide = false
            m.gKeep = true
            openGuide()
        else
            showPendingResults()
        end if
    else if key = "play" then
        togglePause()
    else if key = "a" then
        toggleFavPlaying()
    else if key = "b" then
        toggleCaptions()
    else if key = "options" then
        showPlayMenu()
    else if m.vodPlaying then
        if key = "left" or key = "replay" then
            vodSeek(-10)
        else if key = "right" then
            vodSeek(10)
        else if key = "rewind" then
            vodSeek(-60)
        else if key = "fastforward" then
            vodSeek(60)
        end if
    else
        if key = "up" then
            zap(-1)
        else if key = "down" then
            zap(1)
        else if key = "left" then
            openGuide()
        end if
    end if
end sub

sub togglePause()
    st = m.video.state
    if st = "paused" then
        m.video.control = "resume"
        hideStatus()
    else if st = "playing" or st = "buffering" then
        m.video.control = "pause"
        showStatus("Paused   (Play/Pause to resume)", 0)
    end if
end sub

sub vodSeek(delta as Integer)
    dur = Int(m.video.duration)
    target = Int(m.video.position) + delta
    if target < 0 then target = 0
    if dur > 10 and target > dur - 5 then target = dur - 5
    m.video.seek = target
    showStatus(fmtDur(target) + " / " + fmtDur(dur), 2)
end sub

' First OK shows the info screen, the next OK opens the playback options.
sub playerOk()
    if m.nerd.visible then
        toggleNerd()
        return
    end if
    if m.okPrompt then
        m.okPrompt = false
        m.ovHelp.visible = false
        showPlayMenu()
    else
        showInfo()
    end if
end sub

sub showInfo()
    if m.vodPlaying then updateVodBanner()
    m.ovHelp.text = "OK again: playback options     Play/Pause: pause / resume     A: favorite     B: captions     Back: stop"
    m.ovHelp.visible = true
    m.okPrompt = true
    showOverlayFor(8)
    m.nerdTimer.control = "stop"
    m.nerdTimer.control = "start"
end sub

' ---------------------------------------------------------------------
' Favorite of whatever is playing (an episode counts for its series)
' ---------------------------------------------------------------------

function playingFavId() as String
    if m.vodPlaying then
        d = m.vod
        if d.kind = "episode" then return d.sid
        return d.id
    end if
    return m.playingId
end function

function isFavPlaying() as Boolean
    id = playingFavId()
    if id = "" then return false
    return isFav(id)
end function

sub toggleFavPlaying()
    if m.vodPlaying then
        toggleFavDetail(m.vod)
    else
        toggleFav(m.playingId, m.playingName, m.playingIcon)
    end if
end sub

' favorite of a movie / episode detail record (an episode counts for its series)
sub toggleFavDetail(d as Object)
    if d.kind = "episode" then
        sd = m.seriesData
        if sd <> invalid and sd.id = d.sid then
            toggleFav(sd.id, sd.name, sd.cover)
        else
            showStatus("Open the series from the Series list to add it to Favorites", 4)
        end if
    else
        toggleFav(d.id, d.title, d.icon)
    end if
end sub

function favIdOfDetail(d as Object) as String
    if d.kind = "episode" then return d.sid
    return d.id
end function

' ---------------------------------------------------------------------
' Audio tracks (some files have a silent or unsupported default track)
' ---------------------------------------------------------------------

function audioTrackName(t as Object) as String
    nm = firstS(t, ["Name", "Description"])
    lang = firstS(t, ["Language"])
    out = nm
    if lang <> "" then
        if out = "" then
            out = lang
        else
            out = out + " (" + lang + ")"
        end if
    end if
    if out = "" then out = "track " + firstS(t, ["Track"])
    return out
end function

function audioTracksList() as Object
    tracks = fldOf(m.video, "availableAudioTracks")
    if type(tracks) = "roArray" then return tracks
    return []
end function

function currentAudioIndex(tracks as Object) as Integer
    cur = toS(fldOf(m.video, "currentAudioTrack"))
    for i = 0 to tracks.Count() - 1
        if type(tracks[i]) = "roAssociativeArray" then
            if toS(tracks[i].Track) = cur then return i
        end if
    end for
    return 0
end function

sub cycleAudioTrack()
    tracks = audioTracksList()
    n = tracks.Count()
    if n < 2 then return
    nxt = currentAudioIndex(tracks) + 1
    if nxt >= n then nxt = 0
    t = tracks[nxt]
    if type(t) <> "roAssociativeArray" then return
    if m.video.hasField("audioTrack") then m.video.audioTrack = toS(t.Track)
    showStatus("Audio: " + audioTrackName(t), 4)
end sub

' ---------------------------------------------------------------------
' Playback options (second OK press)
' ---------------------------------------------------------------------

sub showPlayMenu()
    labels = []
    m.menuActs = []

    if not m.vodPlaying then
        labels.push("Open channel guide")
        m.menuActs.push("guide")
    end if

    if not m.nerd.visible then
        labels.push("Show stream info")
        m.menuActs.push("info")
    end if

    favLbl = "Add to favorites"
    if isFavPlaying() then favLbl = "Remove from favorites"
    if m.vodPlaying then
        if m.vod.kind = "episode" then favLbl = favLbl + "  (series)"
    end if
    labels.push(favLbl)
    m.menuActs.push("fav")

    if not m.vodPlaying then
        swLbl = "Force MPEG-TS (.ts)"
        if m.curExt = "ts" then swLbl = "Force HLS (.m3u8)"
        labels.push(swLbl)
        m.menuActs.push("fmt")

        nxt = m.capChan + 1
        if nxt > 4 then nxt = 1
        labels.push("Caption channel: CC" + m.capChan.ToStr() + "  (select for CC" + nxt.ToStr() + ")")
        m.menuActs.push("cap")
    end if

    tracks = audioTracksList()
    if tracks.Count() > 1 then
        cur = tracks[currentAudioIndex(tracks)]
        nm = ""
        if type(cur) = "roAssociativeArray" then nm = audioTrackName(cur)
        labels.push("Audio track: " + nm + "  (select for next)")
        m.menuActs.push("audio")
    end if

    title = m.playingName
    if m.vodPlaying then title = m.vod.title
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = dlgTitle(title, "Playback options")
    dlg.buttons = labels
    dlg.observeField("buttonSelected", "onPlayMenu")
    m.menuDlg = dlg
    m.top.dialog = dlg
end sub

sub onPlayMenu(event as Object)
    idx = event.getData()
    m.menuDlg.close = true
    if idx < 0 or idx >= m.menuActs.Count() then return
    act = m.menuActs[idx]
    if act = "guide" then
        openGuide()
    else if act = "info" then
        toggleNerd()
    else if act = "fav" then
        toggleFavPlaying()
    else if act = "fmt" then
        if m.curExt = "m3u8" then
            m.triedTs = true
            startStream(m.playingId, "ts")
        else
            startStream(m.playingId, "m3u8")
        end if
    else if act = "cap" then
        cycleCaptionChannel()
    else if act = "audio" then
        cycleAudioTrack()
    end if
end sub

' progress line + title shown for a movie / episode when OK is pressed
sub updateVodBanner()
    d = m.vod
    if d = invalid then return
    setLogo(m.ovLogo, d.icon)
    setRtl(m.ovName, d.title, "font:LargeBoldSystemFont", 36, 0)
    dur = Int(m.video.duration)
    posn = Int(m.video.position)
    txt = fmtDur(posn) + " / " + fmtDur(dur)
    if dur > 0 then txt = txt + "     " + (posn * 100 \ dur).ToStr() + "%"
    if m.video.state = "paused" then txt = txt + "     (paused)"
    txt = txt + Chr(10) + "Left / Right: seek 10 s     Rewind / Fast-forward: 60 s     Replay: back 10 s"
    setRtl(m.ovEpg, txt, "font:MediumSystemFont", 28, 0)
end sub

' full details of a playback error go to the debug log (the on-screen message is brief)
sub logVideoError(where as String)
    v = m.video
    logLine("VIDEO ERROR (" + where + ")  code=" + toS(fldOf(v, "errorCode")) + "  msg=" + toS(fldOf(v, "errorMsg")) + "  str=" + toS(fldOf(v, "errorStr")))
    ei = fldOf(v, "errorInfo")
    if type(ei) = "roAssociativeArray" then logLine("   errorInfo: " + maskUrl(dumpAA(ei)))
    url = ""
    if v.content <> invalid then url = v.content.url
    logLine("   videoFormat=" + toS(fldOf(v, "videoFormat")) + "  audioFormat=" + toS(fldOf(v, "audioFormat")) + "  url=" + maskUrl(url))
end sub

' a few seconds after a movie starts: warn when the Roku found no playable audio
sub onAudioCheck()
    if not m.vodPlaying then return
    af = toS(fldOf(m.video, "audioFormat"))
    vf = toS(fldOf(m.video, "videoFormat"))
    logLine("audio check: video=" + vf + "  audio=" + af + "  provider says audio=" + toS(m.vod.ainfo))
    if af = "none" then
        msg = "No sound: the Roku cannot play this file's audio format"
        if toS(m.vod.ainfo) <> "" then msg = msg + " (" + toS(m.vod.ainfo) + ")"
        showStatus(msg, 8)
    end if
end sub
