sub init()
    m.name = m.top.findNode("name")
    f = CreateObject("roSGNode", "Font")
    f.uri = "font:SystemFontFile"
    f.size = 30
    m.latFont = f
    m.name.font = f
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    setRtl(m.name, c.title, m.latFont, 30, 0)
end sub

sub onFocus()
    if m.top.itemHasFocus then
        m.name.color = "0xFFFFFFFF"
        m.name.repeatCount = -1
    else
        m.name.color = "0xC8D1DCFF"
        m.name.repeatCount = 0
    end if
end sub
