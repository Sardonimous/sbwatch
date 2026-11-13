' =====================================================================
' Favorites list management (included by MainScene; shares its "m" scope)
' On the Favorites list, "*" opens a menu: Move / Move to top / Remove.
' Move mode: Up/Down reposition the channel, OK drops it, Back cancels.
' The order is saved to the registry after every step.
' =====================================================================

sub favInit()
    m.favMove = invalid
    m.favDlg = invalid
    m.favMenuIdx = 0
    m.favTimer = m.top.findNode("favTimer")
    m.favTimer.observeField("fire", "onFavTimer")
end sub

' Returns a copy of arr with the element at fromIdx moved to toIdx.
function favReorderArray(arr as Object, fromIdx as Integer, toIdx as Integer) as Object
    n = arr.Count()
    if fromIdx < 0 or fromIdx >= n or toIdx < 0 or toIdx >= n or fromIdx = toIdx then return arr
    e = arr[fromIdx]
    rest = []
    for i = 0 to n - 1
        if i <> fromIdx then rest.push(arr[i])
    end for
    out = []
    for i = 0 to n - 1
        if i = toIdx then out.push(e)
        if i < rest.Count() then out.push(rest[i])
    end for
    return out
end function

' True when the visible list really is the saved favorites (same order).
function favListInSync(idx as Integer, id as String) as Boolean
    favs = loadList("favs")
    if idx < 0 or idx >= favs.Count() then return false
    return favs[idx].id = id
end function

sub showFavMenu()
    item = currentFocusedItem()
    if item = invalid then return
    m.favMenuIdx = m.chList.itemFocused

    if not favListInSync(m.favMenuIdx, item.id) then
        ' list and saved data disagree: just reload the saved favorites
        m.chList.content = nodeFromList(loadList("favs"))
        showStatus("Favorites reloaded - press * again", 3)
        return
    end if

    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = chanName(item)
    dlg.message = ["Favorites"]
    dlg.buttons = ["Move (Up/Down, then OK)", "Move to top", "Remove from favorites", "Cancel"]
    dlg.observeField("buttonSelected", "onFavMenu")
    m.favDlg = dlg
    m.top.dialog = dlg
end sub

sub onFavMenu(event as Object)
    idx = event.getData()
    m.favDlg.close = true
    fpos = m.favMenuIdx
    c = m.chList.content
    if c = invalid then return
    item = c.getChild(fpos)
    if item = invalid then return

    if idx = 0 then
        startFavMove(fpos)
    else if idx = 1 then
        favs = loadList("favs")
        if fpos > 0 and fpos < favs.Count() then
            favs = favReorderArray(favs, fpos, 0)
            saveList("favs", favs)
            m.chList.content = nodeFromList(favs)
            m.chList.jumpToItem = 0
            showStatus("Moved to top", 2)
        end if
    else if idx = 2 then
        toggleFav(item.id, chanName(item), item.HDPosterUrl)
    end if
end sub

sub startFavMove(fpos as Integer)
    m.favMove = { idx: fpos, startIdx: fpos, orig: loadList("favs"), busy: false }
    showStatus("Moving channel:  Up / Down to reposition,  OK to drop,  Back to cancel", 0)
end sub

' Called from onChFocused while a move is in progress.
sub favMoveFocused()
    fm = m.favMove
    if fm = invalid then return
    if fm.busy then return
    idx = m.chList.itemFocused
    d = idx - fm.idx
    if d <> 1 and d <> -1 then return

    favs = loadList("favs")
    if idx < 0 or idx >= favs.Count() then return
    favs = favReorderArray(favs, fm.idx, idx)
    saveList("favs", favs)

    ' Rebuilding the list resets its focus, which raises focus events of
    ' our own making; ignore them until the short timer fires, then resync.
    fm.busy = true
    fm.idx = idx
    m.chList.content = nodeFromList(favs)
    m.chList.jumpToItem = idx
    m.favTimer.control = "stop"
    m.favTimer.control = "start"
end sub

sub onFavTimer()
    fm = m.favMove
    if fm = invalid then return
    fm.busy = false
    m.chList.jumpToItem = fm.idx
end sub

sub endFavMove(keep as Boolean)
    fm = m.favMove
    m.favMove = invalid
    m.favTimer.control = "stop"
    if fm = invalid then return
    if keep then
        showStatus("Order saved", 2)
    else
        saveList("favs", fm.orig)
        m.chList.content = nodeFromList(fm.orig)
        m.chList.jumpToItem = fm.startIdx
        showStatus("Move cancelled", 2)
    end if
end sub

' Publishes the set of favorite channel ids so list items can show a star.
sub refreshFavIds()
    ids = {}
    for each e in loadList("favs")
        ids[e.id] = true
    end for
    m.global.favIds = ids
end sub
