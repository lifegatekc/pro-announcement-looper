function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.isScreensaver then return false
    if m.top.dialog <> invalid
        if m.top.dialog.visible then return false
    end if
    if m.playing and not m.menu.visible and (key = "play" or key = "pause" or key = "playonly")
        if key = "pause"
            if not m.paused then togglePause()
        else if key = "playonly"
            if m.paused then togglePause()
        else
            togglePause()
        end if
        return true
    end if
    if m.page = "rule:minute" and m.menu.visible and (key = "left" or key = "right")
        offset = 10
        if key = "left" then offset = -10
        m.list.jumpToItem = (m.list.itemFocused + offset + 60) mod 60
        return true
    end if
    if key = "back"
        if m.playing and not m.menu.visible
            stopLoop()
            return true
        end if
        if Left(m.page,5) = "rule:"
            if m.page = "rule:list"
                showPage("schedule")
            else if m.page = "rule:edit"
                showSwitchTimes()
            else
                showRuleEditor()
            end if
        else if m.page = "detail" or m.page = "libraries"
            m.addingPresentation = false
            showConfigured()
        else if m.page = "presentations"
            browsePresentations()
        else if m.page = "showMode" or m.page = "intervalPicker"
            showPage("detail")
        else if m.page <> "home"
            home()
        else if m.playing
            if m.menu.visible
                closeControls()
            else
                stopLoop()
            end if
        else if not m.busy or m.startupRefreshing
            m.top.exitRequested = true
        end if
        return true
    else if key = "options" and m.playing
        if m.demoMode
            stopLoop()
            return true
        end if
        if m.menu.visible
            closeControls()
        else
            m.menuAutoPaused = not m.paused
            if m.menuAutoPaused then togglePause()
            m.menu.visible = true
            home()
        end if
        return true
    else if m.playing and not m.menu.visible
        if key = "right" or key = "left"
            if m.deck.files.Count() <= 1 then return true
            m.slideTimer.control = "stop"
            index = m.index + 1
            if key = "left" then index = (m.index + m.deck.files.Count() - 1) mod m.deck.files.Count()
            loadSlide(index)
            return true
        end if
    end if
    return false
end function
