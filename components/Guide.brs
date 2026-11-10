' =====================================================================
' Full grid guide (included by MainScene; shares its "m" scope)
' Rows = channels of the category currently in the channel list.
' The hidden channel list keeps remote focus: Up/Down change its
' selection (= guide row), Left/Right/Back/etc. bubble to onKeyEvent.
' EPG is fetched lazily (get_short_epg) only for the visible rows.
' =====================================================================

sub guideInit()
    m.guide = m.top.findNode("guide")
    m.gHead = m.top.findNode("gHead")
    m.gRowsG = m.top.findNode("gRowsG")
    m.gNowLine = m.top.findNode("gNowLine")
    m.gClock = m.top.findNode("gClock")
    m.gTitle = m.top.findNode("gTitle")
    m.gdChan = m.top.findNode("gdChan")
    m.gdTitle = m.top.findNode("gdTitle")
    m.gdTime = m.top.findNode("gdTime")
    m.gdDesc = m.top.findNode("gdDesc")

    m.gRows = 8
    m.gRowH = 88
    m.gY0 = 178
    m.gChanX = 60
    m.gChanW = 370
    m.gTimeX = 440
    m.gTimeW = 1420
    m.gSpan = 10800
    m.gPer = 10

    m.guideOpen = false
    m.guideBuilt = false
    m.gKeep = false
    m.gBase = 0
    m.gWin = 0
    m.gSel = 0
    m.gTop = 0
end sub

sub buildGuide()
    m.gHeadLbl = []
    for k = 0 to 6
        lbl = CreateObject("roSGNode", "Label")
        lbl.font = "font:SmallSystemFont"
        lbl.color = "0xA9B6C6FF"
        lbl.width = 220
        lbl.visible = false
        m.gHead.appendChild(lbl)
        m.gHeadLbl.push(lbl)
    end for

    m.gChBg = []
    m.gChLbl = []
    m.gChLogo = []
    m.gBg = []
    m.gTt = []
    m.gTm = []

    for r = 0 to m.gRows - 1
        y = m.gY0 + r * m.gRowH

        cb = CreateObject("roSGNode", "Rectangle")
        cb.translation = [m.gChanX, y]
        cb.width = m.gChanW
        cb.height = m.gRowH - 8
        cb.color = "0x141B24FF"
        cb.visible = false
        m.gRowsG.appendChild(cb)
        m.gChBg.push(cb)

        cl = CreateObject("roSGNode", "Label")
        cl.translation = [m.gChanX + 84, y]
        cl.width = m.gChanW - 96
        cl.height = m.gRowH - 8
        cl.vertAlign = "center"
        cl.font = "font:MediumSystemFont"
        cl.color = "0xFFFFFFFF"
        cl.visible = false
        m.gRowsG.appendChild(cl)
        m.gChLbl.push(cl)

        lg = CreateObject("roSGNode", "Poster")
        lg.translation = [m.gChanX + 10, y + 22]
        lg.width = 64
        lg.height = 36
        lg.loadDisplayMode = "scaleToFit"
        lg.loadWidth = 128
        lg.loadHeight = 72
        lg.visible = false
        m.gRowsG.appendChild(lg)
        m.gChLogo.push(lg)

        for ci = 0 to m.gPer - 1
            bg = CreateObject("roSGNode", "Rectangle")
            bg.visible = false
            m.gRowsG.appendChild(bg)
            m.gBg.push(bg)

            tt = CreateObject("roSGNode", "Label")
            tt.font = "font:SmallBoldSystemFont"
            tt.height = 34
            tt.visible = false
            m.gRowsG.appendChild(tt)
            m.gTt.push(tt)

            tm = CreateObject("roSGNode", "Label")
            tm.font = "font:SmallestSystemFont"
            tm.height = 28
            tm.visible = false
            m.gRowsG.appendChild(tm)
            m.gTm.push(tm)
        end for
    end for
    m.guideBuilt = true
end sub

sub openGuide()
    c = m.chList.content
    if c = invalid then
        showStatus("Open a category first", 3)
        return
    end if
    if c.getChildCount() = 0 then
        showStatus("No channels to show", 3)
        return
    end if
    if not m.guideBuilt then buildGuide()

    if m.gKeep and m.gBase > 0 then
        m.gKeep = false
    else
        m.gKeep = false
        now = nowSecs()
        m.gBase = now - (now mod 1800)
        m.gWin = m.gBase
        m.gSel = now
        m.gTop = 0
    end if
    m.guideOpen = true
    m.overlay.visible = false
    m.guide.visible = true
    m.gTitle.text = "Channel Guide"
    m.chList.setFocus(true)
    drawGuide()
end sub

sub closeGuide()
    m.guideOpen = false
    m.guide.visible = false
    m.chList.setFocus(true)
    if not m.video.visible then scheduleEpg()
end sub

' Segments of one row over [gBase, gBase + 12h]: programmes plus
' "gap" segments for missing data, so every instant belongs to a segment.
function rowSegments(id as String) as Object
    segs = []
    lo = m.gBase
    hi = m.gBase + 43200

    if not m.epgCache.DoesExist(id) then
        segs.push({ s: lo, e: hi, title: "Loading guide ...", desc: "", kind: "load", ps: 0, pe: 0 })
        return segs
    end if

    entry = m.epgCache[id]
    t = lo
    for each l in entry.listings
        if l.stop > t and l.start < hi then
            st = l.start
            if st < t then st = t
            if st > t then
                segs.push({ s: t, e: st, title: "No guide data", desc: "", kind: "gap", ps: 0, pe: 0 })
            end if
            en = l.stop
            if en > hi then en = hi
            segs.push({ s: st, e: en, title: l.title, desc: l.desc, kind: "prog", ps: l.start, pe: l.stop })
            t = en
        end if
    end for
    if t < hi then
        segs.push({ s: t, e: hi, title: "No guide data", desc: "", kind: "gap", ps: 0, pe: 0 })
    end if
    return segs
end function

function segIndexAt(segs as Object, t as Integer) as Integer
    if segs.Count() = 0 then return 0
    if t < segs[0].s then return 0
    for i = 0 to segs.Count() - 1
        if segs[i].s <= t and t < segs[i].e then return i
    end for
    return segs.Count() - 1
end function

sub guideCell(k as Integer, x as Integer, y as Integer, w as Integer, sg as Object, focused as Boolean, now as Integer)
    bg = m.gBg[k]
    tt = m.gTt[k]
    tm = m.gTm[k]

    col = "0x10151CFF"
    tcol = "0x6B7A8CFF"
    if sg.kind = "prog" then
        col = "0x1B2430FF"
        tcol = "0xFFFFFFFF"
        if sg.ps <= now and now < sg.pe then col = "0x1E3A2BFF"
    end if
    tmcol = "0xA9B6C6FF"
    if focused then
        col = "0x2563EBFF"
        tcol = "0xFFFFFFFF"
        tmcol = "0xDCE6FFFF"
    end if

    bg.translation = [x, y]
    bg.width = w
    bg.height = m.gRowH - 8
    bg.color = col
    bg.visible = true

    if w > 70 then
        tt.translation = [x + 10, y + 8]
        tt.width = w - 20
        tt.text = sg.title
        tt.color = tcol
        tt.visible = true
        if sg.kind = "prog" and w > 120 then
            tm.translation = [x + 10, y + 46]
            tm.width = w - 20
            tm.text = fmtTime(sg.ps) + " - " + fmtTime(sg.pe)
            tm.color = tmcol
            tm.visible = true
        else
            tm.visible = false
        end if
    else
        tt.visible = false
        tm.visible = false
    end if
end sub

sub drawGuide()
    if not m.guideOpen then return
    c = m.chList.content
    if c = invalid then return
    n = c.getChildCount()
    if n = 0 then return

    sel = m.chList.itemFocused
    if sel < 0 then sel = 0
    if sel >= n then sel = n - 1
    if sel < m.gTop then m.gTop = sel
    if sel >= m.gTop + m.gRows then m.gTop = sel - m.gRows + 1

    now = nowSecs()
    pps = m.gTimeW / m.gSpan
    win = m.gWin
    winEnd = win + m.gSpan

    m.gClock.text = "Now " + fmtTime(now)

    for k = 0 to 6
        lbl = m.gHeadLbl[k]
        lbl.text = fmtTime(win + k * 1800)
        lbl.translation = [m.gTimeX + Int(k * 1800 * pps), 138]
        lbl.visible = true
    end for

    m.epgWanted = {}
    if m.playingId <> "" then m.epgWanted[m.playingId] = true

    selSeg = invalid
    selChan = ""

    for r = 0 to m.gRows - 1
        idx = m.gTop + r
        base = r * m.gPer
        y = m.gY0 + r * m.gRowH

        if idx < n then
            item = c.getChild(idx)
            id = item.id
            m.epgWanted[id] = true
            if cachedEpg(id) = invalid then requestEpg(id)

            isSel = false
            if idx = sel then isSel = true

            m.gChBg[r].color = "0x141B24FF"
            m.gChLbl[r].color = "0xFFFFFFFF"
            if isSel then
                m.gChBg[r].color = "0x2563EBFF"
            end if
            m.gChBg[r].visible = true
            m.gChLbl[r].text = chanName(item)
            m.gChLbl[r].visible = true
            setLogo(m.gChLogo[r], item.HDPosterUrl)

            segs = rowSegments(id)
            si = segIndexAt(segs, m.gSel)
            cnt = 0
            for i = 0 to segs.Count() - 1
                sg = segs[i]
                if sg.e > win and sg.s < winEnd and cnt < m.gPer then
                    a = sg.s
                    if a < win then a = win
                    b = sg.e
                    if b > winEnd then b = winEnd
                    x = m.gTimeX + Int((a - win) * pps)
                    w = Int((b - a) * pps) - 3
                    if w < 4 then w = 4
                    foc = false
                    if isSel and i = si then foc = true
                    guideCell(base + cnt, x, y, w, sg, foc, now)
                    cnt = cnt + 1
                end if
            end for
            for ci = cnt to m.gPer - 1
                m.gBg[base + ci].visible = false
                m.gTt[base + ci].visible = false
                m.gTm[base + ci].visible = false
            end for

            if isSel then
                selSeg = segs[si]
                selChan = chanName(item)
            end if
        else
            m.gChBg[r].visible = false
            m.gChLbl[r].visible = false
            m.gChLogo[r].visible = false
            for ci = 0 to m.gPer - 1
                m.gBg[base + ci].visible = false
                m.gTt[base + ci].visible = false
                m.gTm[base + ci].visible = false
            end for
        end if
    end for

    if now >= win and now <= winEnd then
        m.gNowLine.translation = [m.gTimeX + Int((now - win) * pps), m.gY0 - 4]
        m.gNowLine.visible = true
    else
        m.gNowLine.visible = false
    end if

    m.gdChan.text = selChan
    if selSeg <> invalid then
        m.gdTitle.text = selSeg.title
        if selSeg.kind = "prog" then
            mins = Int((selSeg.pe - selSeg.ps) / 60)
            m.gdTime.text = fmtTime(selSeg.ps) + " - " + fmtTime(selSeg.pe) + "   (" + mins.ToStr() + " min)"
            m.gdDesc.text = selSeg.desc
        else
            m.gdTime.text = ""
            m.gdDesc.text = ""
        end if
    end if
end sub

sub guideMove(dir as Integer)
    item = currentFocusedItem()
    if item = invalid then return
    segs = rowSegments(item.id)
    i = segIndexAt(segs, m.gSel)
    j = i + dir
    if j < 0 or j >= segs.Count() then return
    t = segs[j].s

    m.gSel = t
    ws = m.gWin
    if t < ws then
        ws = t - (t mod 1800)
    else if t >= ws + m.gSpan - 1800 then
        ws = t - (t mod 1800) - 1800
    end if
    if ws < m.gBase then ws = m.gBase
    m.gWin = ws
    drawGuide()
end sub

sub guidePage(dir as Integer)
    c = m.chList.content
    if c = invalid then return
    n = c.getChildCount()
    idx = m.chList.itemFocused + dir * m.gRows
    if idx < 0 then idx = 0
    if idx >= n then idx = n - 1
    m.chList.jumpToItem = idx
end sub

sub guideNow()
    m.gWin = m.gBase
    m.gSel = nowSecs()
    drawGuide()
end sub
