sub init()
    m.top.backgroundColor = "0x000000FF"
    for each id in ["front", "back", "validator", "menu", "heading", "summary", "list", "status", "notice", "slideTimer", "loadTimer", "validateTimer", "noticeTimer", "heartbeat", "startup"]
        m[id] = m.top.FindNode(id)
    end for
    m.list.ObserveField("itemSelected", "onSelected")
    m.slideTimer.ObserveField("fire", "onSlideTimer")
    m.loadTimer.ObserveField("fire", "onLoadTimeout")
    m.validateTimer.ObserveField("fire", "onValidationTimeout")
    m.noticeTimer.ObserveField("fire", "hideNotice")
    m.heartbeat.ObserveField("fire", "onHeartbeat")
    m.startup.ObserveField("fire", "startApp")
    m.front.ObserveField("loadStatus", "onPoster")
    m.back.ObserveField("loadStatus", "onPoster")
    m.validator.ObserveField("loadStatus", "onValidated")
    m.settings = DefaultSettings()
    m.deck = invalid
    m.candidate = invalid
    m.validating = false
    m.worker = invalid
    m.busy = false
    m.playing = false
    m.loading = false
    m.page = "home"
    m.index = -1
    m.started = CreateObject("roTimespan")
    m.cycles = 0
    m.lowMemory = false
    m.startAfterRefresh = false
    m.status.text = "Loading settings..."
    m.top.SetFocus(true)
    m.startup.control = "start"
end sub

sub onMode()
    ' Read at startup, after the entry point has supplied the mode.
end sub

sub startApp()
    m.isScreensaver = m.top.mode = "screensaver"
    m.menu.visible = not m.isScreensaver
    request({action: "init", mode: m.top.mode})
    m.heartbeat.control = "start"
end sub

sub request(data as object)
    if m.busy then return
    m.busy = true
    if m.worker <> invalid
        m.worker.UnobserveField("result")
        m.worker.UnobserveField("progress")
        m.top.RemoveChild(m.worker)
    end if
    m.worker = m.top.CreateChild("ApiWorker")
    m.worker.ObserveField("result", "onResult")
    m.worker.ObserveField("progress", "onProgress")
    m.worker.request = data
    m.worker.control = "RUN"
end sub

sub onProgress()
    m.status.text = m.worker.progress
    if m.playing then showNotice(m.worker.progress)
end sub

sub onResult()
    r = m.worker.result
    m.busy = false
    if not r.ok
        if r.action = "commit" and m.candidate <> invalid
            rejectCandidate(r.error)
            return
        end if
        m.status.text = r.error
        showNotice(r.error)
        if m.isScreensaver and not m.playing then m.notice.visible = true
        return
    end if
    if r.action = "init"
        m.settings = r.settings
        m.deck = r.cached
        home()
        if m.isScreensaver
            if m.deck <> invalid
                startLoop()
            else
                refreshDeck()
            end if
        else
            m.status.text = "Choose a profile and presentation, then Start slideshow."
            if m.deck <> invalid then m.status.text = "Cached slides ready. Start slideshow or Refresh now."
        end if
    else if r.action = "save"
        home()
        m.status.text = "Settings saved."
    else if r.action = "libraries"
        showItems("libraries", "Choose a library", r.items)
    else if r.action = "presentations"
        showItems("presentations", "Choose an announcements presentation", r.items)
    else if r.action = "fetch"
        m.candidate = r.deck
        if m.lowMemory
            rejectCandidate("Roku memory is low.")
            return
        end if
        m.validationIndex = 0
        m.validating = true
        m.busy = true
        validateNext()
    else if r.action = "commit"
        m.deck = r.deck
        m.candidate = invalid
        m.status.text = "Refresh complete: " + m.deck.files.Count().ToStr() + " slides."
        if m.playing
            m.slideTimer.control = "stop"
            m.loadTimer.control = "stop"
            m.loading = false
            m.back.uri = ""
            loadSlide(0)
        else if m.isScreensaver or m.startAfterRefresh
            m.startAfterRefresh = false
            startLoop()
        end if
        showNotice("Slides refreshed.")
        if m.page = "home" then updateSummary()
    else if r.action = "discard"
        m.candidate = invalid
        m.status.text = "Refresh cancelled: " + m.validationError + " Existing slideshow retained."
        showNotice(m.status.text)
    end if
end sub

sub home()
    m.page = "home"
    m.heading.text = "Pro Announcement Looper"
    if m.top.mode = "settings" then m.heading.text = "Pro Announcement Looper - screensaver settings"
    m.actions = ["start", "refresh", "profile", "address", "browse", "duration", "help"]
    p = m.settings.profiles[m.settings.selected]
    labels = ["Start slideshow", "Refresh now", "Profile: " + p.label + " (select to switch)", "ProPresenter computer address", "Choose presentation from ProPresenter", "Slide duration: " + p.seconds.ToStr() + " seconds", "Unattended playback setup / status"]
    if m.top.mode = "settings"
        labels[0] = "Preview slideshow"
    end if
    setList(labels)
    updateSummary()
end sub

sub updateSummary()
    p = m.settings.profiles[m.settings.selected]
    name = p.name
    if name = "" then name = "No presentation selected"
    address = m.settings.baseUrl
    if address = "" then address = "Computer address not set"
    cache = "No matching cache"
    if ValidCache(m.deck, DeckIdentity(m.settings))
        cache = m.deck.files.Count().ToStr() + " cached slides | " + m.deck.cachedAt
    end if
    m.summary.text = p.label + " | " + name + Chr(10) + address + Chr(10) + cache
end sub

sub setList(labels as object)
    content = CreateObject("roSGNode", "ContentNode")
    for each label in labels
        item = content.CreateChild("ContentNode")
        item.title = label
    end for
    m.list.content = content
    m.list.jumpToItem = 0
    if not m.isScreensaver then m.list.SetFocus(true)
end sub

sub showItems(page as string, title as string, items as object)
    m.page = page
    m.heading.text = title
    m.items = items
    labels = []
    for each item in items
        labels.Push(item.name)
    end for
    if labels.Count() = 0 then labels.Push("No items found - press Back")
    setList(labels)
    m.status.text = "Select with OK. Back returns to settings."
end sub

sub onSelected()
    if m.busy
        showNotice("Please wait for the current operation to finish.")
        return
    end if
    index = m.list.itemSelected
    if m.page = "libraries"
        if index >= m.items.Count() then return
        request({action: "presentations", settings: m.settings, library: m.items[index].name})
        m.status.text = "Reading presentations..."
        return
    else if m.page = "presentations"
        if index >= m.items.Count() then return
        selected = m.items[index]
        if m.playing then stopLoop()
        p = m.settings.profiles[m.settings.selected]
        p.uuid = selected.uuid
        p.name = selected.name
        saveSettings()
        return
    end if
    action = m.actions[index]
    if action = "start"
        startLoop()
    else if action = "refresh"
        refreshDeck()
    else if action = "profile"
        if m.playing then stopLoop()
        m.settings.selected = 1 - m.settings.selected
        saveSettings()
    else if action = "address"
        editValue("address", "ProPresenter address (example: 192.168.1.50:50001)", m.settings.baseUrl)
    else if action = "browse"
        if m.settings.baseUrl = ""
            showNotice("Set the ProPresenter computer address first.")
        else
            m.status.text = "Reading libraries..."
            request({action: "libraries", settings: m.settings})
        end if
    else if action = "duration"
        editValue("duration", "Seconds per slide (1-3600)", m.settings.profiles[m.settings.selected].seconds.ToStr())
    else if action = "help"
        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title = "Unattended playback"
        dialog.message = "Turn off Roku Bandwidth saver and Auto power savings. Select Pro Announcement Looper as the system screensaver. Player and screensaver must use the same developer signing key to share settings. Screensaver maintains its own cache. Home always leaves the app. Runtime: " + Int(m.started.TotalMilliseconds() / 60000).ToStr() + " minutes; completed loops: " + m.cycles.ToStr() + "."
        dialog.buttons = ["Close"]
        dialog.ObserveField("buttonSelected", "closeDialog")
        m.top.dialog = dialog
    end if
end sub

sub editValue(kind as string, title as string, value as string)
    m.editKind = kind
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = title
    dialog.text = value
    dialog.buttons = ["Save", "Cancel"]
    dialog.ObserveField("buttonSelected", "onEdit")
    m.top.dialog = dialog
end sub

sub onEdit()
    dialog = m.top.dialog
    if dialog.buttonSelected = 0
        value = dialog.text.Trim()
        if m.editKind = "address"
            address = NormalizeBaseUrl(value)
            if address = ""
                showNotice("Enter a host or IPv4 address with an optional port. Default port: 50001.")
                return
            end if
            if m.playing then stopLoop()
            m.settings.baseUrl = address
        else
            digits = CreateObject("roRegex", "^[0-9]{1,4}$", "")
            if not digits.IsMatch(value)
                showNotice("Enter a whole number from 1 to 3600.")
                return
            end if
            seconds = Val(value)
            if seconds < 1 or seconds > 3600
                showNotice("Enter a whole number from 1 to 3600.")
                return
            end if
            m.settings.profiles[m.settings.selected].seconds = Int(seconds)
        end if
        dialog.close = true
        saveSettings()
    else
        dialog.close = true
        m.list.SetFocus(true)
    end if
end sub

sub closeDialog()
    m.top.dialog.close = true
    m.list.SetFocus(true)
end sub

sub saveSettings()
    request({action: "save", settings: m.settings})
end sub

sub refreshDeck()
    if m.busy then return
    if m.lowMemory
        showNotice("Refresh paused because Roku memory is low. Stop playback and try again.")
        return
    end if
    m.status.text = "Connecting to ProPresenter..."
    request({action: "fetch", mode: m.top.mode, settings: m.settings, keep: m.deck})
end sub

sub validateNext()
    if m.validationIndex >= m.candidate.files.Count()
        m.validating = false
        m.validator.uri = ""
        m.busy = false
        request({action: "commit", mode: m.top.mode, settings: m.settings, deck: m.candidate})
        return
    end if
    m.status.text = "Checking slide " + (m.validationIndex + 1).ToStr() + " of " + m.candidate.files.Count().ToStr()
    m.validateTimer.control = "stop"
    m.validator.uri = ""
    m.validator.uri = m.candidate.files[m.validationIndex]
    m.validateTimer.control = "start"
end sub

sub onValidated()
    if not m.validating then return
    if m.candidate = invalid then return
    if m.validator.loadStatus = "ready"
        m.validateTimer.control = "stop"
        m.validationIndex++
        validateNext()
    else if m.validator.loadStatus = "failed"
        rejectCandidate("Roku could not decode a slide image.")
    end if
end sub

sub onValidationTimeout()
    rejectCandidate("Timed out checking an image.")
end sub

sub rejectCandidate(reason as string)
    m.validating = false
    m.validateTimer.control = "stop"
    m.validator.uri = ""
    m.validationError = reason
    m.busy = false
    candidate = m.candidate
    m.candidate = invalid
    request({action: "discard", deck: candidate})
end sub

sub startLoop()
    if m.busy then return
    if not ValidCache(m.deck, DeckIdentity(m.settings))
        m.startAfterRefresh = true
        refreshDeck()
        return
    end if
    m.menu.visible = false
    m.playing = true
    m.loading = false
    m.top.SetFocus(true)
    m.slideTimer.control = "stop"
    loadSlide(0)
end sub

sub stopLoop()
    m.playing = false
    m.loading = false
    m.slideTimer.control = "stop"
    m.loadTimer.control = "stop"
    m.back.uri = ""
    m.menu.visible = true
    home()
end sub

sub loadSlide(index as integer)
    if not m.playing or m.deck = invalid then return
    m.nextIndex = index mod m.deck.files.Count()
    m.loading = true
    m.loadTimer.control = "stop"
    m.back.uri = ""
    m.back.uri = m.deck.files[m.nextIndex]
    m.loadTimer.control = "start"
end sub

sub onPoster()
    if not m.loading then return
    if m.back.loadStatus = "ready"
        m.loading = false
        m.loadTimer.control = "stop"
        m.back.opacity = 1
        m.front.opacity = 0
        m.front.uri = ""
        previous = m.front
        m.front = m.back
        m.back = previous
        if m.nextIndex = 0 and m.index >= 0 then m.cycles++
        m.index = m.nextIndex
        scheduleSlide()
    else if m.back.loadStatus = "failed"
        slideFailed()
    end if
end sub

sub onLoadTimeout()
    if m.loading then slideFailed()
end sub

sub slideFailed()
    m.loading = false
    m.loadTimer.control = "stop"
    m.back.uri = ""
    m.index = m.nextIndex
    showNotice("A cached slide is unavailable. Use Refresh now when ProPresenter is available.")
    ' Retain the last displayed image and try the next slide after the regular interval.
    scheduleSlide()
end sub

sub scheduleSlide()
    m.slideTimer.control = "stop"
    m.slideTimer.duration = m.settings.profiles[m.settings.selected].seconds
    if m.playing then m.slideTimer.control = "start"
end sub

sub onSlideTimer()
    loadSlide(m.index + 1)
end sub

sub showNotice(message as string)
    m.status.text = message
    m.notice.text = message
    m.notice.visible = not m.menu.visible
    m.noticeTimer.control = "stop"
    m.noticeTimer.control = "start"
end sub

sub hideNotice()
    if m.isScreensaver and not m.playing then return
    m.notice.visible = false
end sub

sub onHeartbeat()
    print "ProAnnouncementLooper uptimeMinutes="; Int(m.started.TotalMilliseconds() / 60000); " loops="; m.cycles; " playing="; m.playing
    if m.isScreensaver and not m.playing and not m.busy
        ' Only retry when there are no playable slides; no network activity during a healthy loop.
        refreshDeck()
    end if
end sub

sub onMemory()
    m.lowMemory = m.top.memoryPercent >= 80
    if m.lowMemory
        print "ProAnnouncementLooper memory warning="; m.top.memoryPercent
        if m.validating then rejectCandidate("Refresh stopped because Roku memory is low.")
    end if
end sub

sub onShutdown()
    m.slideTimer.control = "stop"
    m.loadTimer.control = "stop"
    m.validateTimer.control = "stop"
    m.heartbeat.control = "stop"
    if m.worker <> invalid then m.worker.control = "STOP"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.isScreensaver then return false
    if m.top.dialog <> invalid
        if m.top.dialog.visible then return false
    end if
    if key = "back"
        if m.page <> "home"
            home()
        else if m.playing
            if m.menu.visible
                m.menu.visible = false
                m.top.SetFocus(true)
            else
                stopLoop()
            end if
        else if not m.busy
            m.top.exitRequested = true
        end if
        return true
    else if key = "options" and m.playing
        m.menu.visible = not m.menu.visible
        if m.menu.visible
            home()
        else
            m.top.SetFocus(true)
        end if
        return true
    else if m.playing and not m.menu.visible
        if key = "right" or key = "left"
            m.slideTimer.control = "stop"
            index = m.index + 1
            if key = "left" then index = (m.index + m.deck.files.Count() - 1) mod m.deck.files.Count()
            loadSlide(index)
            return true
        end if
    end if
    return false
end function
