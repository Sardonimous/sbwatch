sub init()
    m.logo = m.top.findNode("logo")
    m.name = m.top.findNode("name")
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.name.text = c.title
    setLogo(m.logo, c.HDPosterUrl)
end sub

sub onFocus()
    if m.top.itemHasFocus then
        m.name.color = "0xFFFFFFFF"
    else
        m.name.color = "0xC8D1DCFF"
    end if
end sub
