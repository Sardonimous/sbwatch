sub init()
    m.logo = m.top.findNode("logo")
    m.name = m.top.findNode("name")
    m.star = m.top.findNode("star")
    m.global.observeField("favIds", "refreshStar")
    m.global.observeField("showFavStars", "refreshStar")
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.name.text = c.title
    setLogo(m.logo, c.HDPosterUrl)
    refreshStar()
end sub

' A star marks channels that are in Favorites (not shown on the Favorites list itself)
sub refreshStar()
    show = false
    c = m.top.itemContent
    if c <> invalid then
        if m.global.showFavStars = true then
            ids = m.global.favIds
            if ids <> invalid then
                if ids.DoesExist(c.id) then show = true
            end if
        end if
    end if
    m.star.visible = show
end sub

sub onFocus()
    if m.top.itemHasFocus then
        m.name.color = "0xFFFFFFFF"
    else
        m.name.color = "0xC8D1DCFF"
    end if
end sub
