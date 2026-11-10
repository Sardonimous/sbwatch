sub init()
    m.bg = m.top.findNode("bg")
    m.accent = m.top.findNode("accent")
    m.badge = m.top.findNode("badge")
    m.time = m.top.findNode("time")
    m.progBg = m.top.findNode("progBg")
    m.progFill = m.top.findNode("progFill")
    m.title = m.top.findNode("title")
    m.desc = m.top.findNode("desc")
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return

    kind = c.kind
    col = "0xA78BFAFF"
    if kind = "NOW" then
        col = "0x2EA44FFF"
    else if kind = "NEXT" then
        col = "0x3B82F6FF"
    end if

    m.accent.color = col
    m.badge.color = col
    m.badge.text = kind
    m.time.text = c.timeText
    m.title.text = c.title
    m.desc.text = c.desc

    if kind = "NOW" then
        p = c.progress
        if p = invalid then p = 0
        if p > 1 then p = 1
        m.progFill.width = 424 * p
        m.progBg.visible = true
        m.progFill.visible = true
    else
        m.progBg.visible = false
        m.progFill.visible = false
    end if
end sub

sub onFocus()
    if m.top.itemHasFocus then
        m.bg.color = "0x2A3A50FF"
    else
        m.bg.color = "0x1B2430FF"
    end if
end sub
