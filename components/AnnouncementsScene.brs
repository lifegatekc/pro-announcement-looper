sub init()
    m.top.backgroundColor = "0x000000FF"
    for each id in ["front", "back", "validator", "menu", "heading", "summary", "list", "status", "notice", "slideTimer", "loadTimer", "validateTimer", "noticeTimer", "heartbeat", "startup", "scheduleTimer"]
        m[id] = m.top.FindNode(id)
    end for
    m.list.ObserveField("itemSelected", "onSelected")
    m.slideTimer.ObserveField("fire", "onSlideTimer")
    m.loadTimer.ObserveField("fire", "onLoadTimeout")
    m.validateTimer.ObserveField("fire", "onValidationTimeout")
    m.noticeTimer.ObserveField("fire", "hideNotice")
    m.scheduleTimer.ObserveField("fire", "onScheduleTick")
    m.heartbeat.ObserveField("fire", "onHeartbeat")
    m.startup.ObserveField("fire", "startApp")
    m.front.ObserveField("loadStatus", "onPoster")
    m.back.ObserveField("loadStatus", "onPoster")
    m.validator.ObserveField("loadStatus", "onValidated")
    m.settings = DefaultSettings()
    m.decks = []
    m.activeProfile = 0
    m.fetchIndex = 0
    m.refreshQueue = []
    m.pendingStart = false
    m.pendingRemote = invalid
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
    m.scheduleTimer.control = "start"
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
        m.refreshQueue = []
        m.startAfterRefresh = false
        m.status.text = r.error
        showNotice(r.error)
        if m.isScreensaver and not m.playing then m.notice.visible = true
        return
    end if
    if r.action = "init"
        m.settings = r.settings
        m.decks = r.decks
        m.activeProfile = m.settings.selected
        m.deck = r.cached
        home()
        if m.isScreensaver
            startLoop()
        else
            m.status.text = "Choose a profile and presentation, then Start slideshow."
            if m.deck <> invalid then m.status.text = "Cached slides ready. Start slideshow or Refresh now."
        end if
    else if r.action = "save"
        home()
        m.status.text = "Settings saved."
        if m.pendingStart
            m.pendingStart = false
            startLoop()
        end if
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
        m.decks[m.fetchIndex] = r.deck
        m.candidate = invalid
        if m.fetchIndex = m.activeProfile
            m.deck = r.deck
            if m.playing
                m.slideTimer.control = "stop"
                m.loadTimer.control = "stop"
                m.loading = false
                m.back.uri = ""
                loadSlide(0)
            end if
        end if
        if m.refreshQueue.Count() > 0
            nextProfile = m.refreshQueue.Shift()
            refreshProfile(nextProfile)
        else
            showNotice("Refresh complete. Other cached profiles are retained.")
            if m.startAfterRefresh
                m.startAfterRefresh = false
                startLoop()
            end if
            if m.page = "home" then updateSummary()
        end if
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
    m.actions = ["start", "switchNow", "resume", "refresh", "refreshAll", "profile", "rename", "add", "browse", "schedule", "scheduleEnabled", "remote", "address", "duration", "help"]
    p = m.settings.profiles[m.settings.selected]
    automation = "Off"
    if m.settings.scheduleEnabled then automation = "On"
    remote = "Off"
    if m.settings.remoteEnabled then remote = "On (player only)"
    labels = ["Start slideshow", "Show selected profile now (hold override)", "Resume schedule", "Refresh now (selected profile)", "Refresh all configured profiles", "Edit profile: " + p.label + " (select for next)", "Rename selected profile", "Add profile", "Choose presentation for selected profile", "Edit switch times for selected profile", "Schedule: " + automation + " (select to toggle)", "Remote actions: " + remote + " (select to toggle)", "ProPresenter computer address", "Slide duration: " + p.seconds.ToStr() + " seconds", "Unattended playback setup / status"]
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
    selectedDeck = m.decks[m.settings.selected]
    if CacheMatches(selectedDeck, DeckIdentity(m.settings))
        cache = selectedDeck.files.Count().ToStr() + " cached slides | " + selectedDeck.cachedAt
    end if
    if m.settings.manualOverride then cache = cache + " | MANUAL HOLD"
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
        m.settings.selected = (m.settings.selected + 1) mod m.settings.profiles.Count()
        saveSettings()
    else if action = "switchNow"
        holdProfile(m.settings.selected)
    else if action = "resume"
        resumeSchedule()
    else if action = "refreshAll"
        refreshAll()
    else if action = "rename"
        editValue("rename", "Profile name", m.settings.profiles[m.settings.selected].label)
    else if action = "add"
        if m.settings.profiles.Count() >= 8
            showNotice("Maximum eight profiles per TV.")
        else
            m.settings.profiles.Push(NewProfile("Profile " + (m.settings.profiles.Count() + 1).ToStr()))
            m.decks.Push(invalid)
            m.settings.selected = m.settings.profiles.Count() - 1
            saveSettings()
        end if
    else if action = "schedule"
        editValue("schedule", "Switch times: Sun 09:00, Sun 11:00 or Daily 08:30", m.settings.profiles[m.settings.selected].schedule)
    else if action = "scheduleEnabled"
        m.settings.scheduleEnabled = not m.settings.scheduleEnabled
        saveSettings()
    else if action = "remote"
        m.settings.remoteEnabled = not m.settings.remoteEnabled
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
        else if m.editKind = "rename"
            if value = "" or Len(value) > 40
                showNotice("Use a profile name of 1 to 40 characters.")
                return
            end if
            m.settings.profiles[m.settings.selected].label = value
        else if m.editKind = "schedule"
            parsed = ParseSchedule(value)
            if not parsed.ok
                showNotice(parsed.error)
                return
            end if
            m.settings.profiles[m.settings.selected].schedule = value
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
    refreshProfile(m.settings.selected)
end sub

sub refreshAll()
    if m.busy then return
    m.refreshQueue = []
    for i = 0 to m.settings.profiles.Count() - 1
        if m.settings.profiles[i].uuid <> "" then m.refreshQueue.Push(i)
    end for
    if m.refreshQueue.Count() = 0
        showNotice("Choose a presentation first.")
        return
    end if
    index = m.refreshQueue.Shift()
    refreshProfile(index)
end sub

sub refreshProfile(index as integer)
    if m.busy then return
    if m.lowMemory
        m.refreshQueue = []
        showNotice("Refresh paused because Roku memory is low. Stop playback and try again.")
        return
    end if
    m.fetchIndex = index
    m.fetchSettings = ProfileSettings(m.settings, index)
    m.status.text = "Caching " + m.settings.profiles[index].label + "..."
    request({action: "fetch", mode: m.top.mode, settings: m.fetchSettings, keep: m.decks[index]})
end sub

sub validateNext()
    if m.validationIndex >= m.candidate.files.Count()
        m.validating = false
        m.validator.uri = ""
        m.busy = false
        request({action: "commit", mode: m.top.mode, settings: m.fetchSettings, deck: m.candidate})
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
    m.refreshQueue = []
    m.startAfterRefresh = false
    m.validationError = reason
    m.busy = false
    candidate = m.candidate
    m.candidate = invalid
    request({action: "discard", deck: candidate})
end sub

function clockTarget() as integer
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    return ScheduledProfile(m.settings, now.GetDayOfWeek(), now.GetHours() * 60 + now.GetMinutes())
end function

sub startLoop()
    if m.busy then return
    target = clockTarget()
    if m.settings.profiles[target].uuid = ""
        showNotice("Choose a presentation for this profile first.")
        return
    end if
    if not profileReady(target)
        m.startAfterRefresh = true
        refreshAll()
        return
    end if
    activateProfile(target)
end sub

function profileReady(index as integer) as boolean
    return CacheMatches(m.decks[index], DeckIdentity(ProfileSettings(m.settings, index)))
end function

sub activateProfile(index as integer)
    deck = m.decks[index]
    if not profileReady(index)
        showNotice("Target profile is not cached. Refresh all profiles before switching.")
        return
    end if
    m.activeProfile = index
    m.deck = deck
    m.menu.visible = false
    m.playing = true
    m.loading = false
    m.top.SetFocus(true)
    m.slideTimer.control = "stop"
    m.loadTimer.control = "stop"
    loadSlide(0)
end sub

sub holdProfile(index as integer)
    if not profileReady(index)
        showNotice("Refresh all profiles first. The current presentation is unchanged.")
        return
    end if
    m.settings.selected = index
    m.settings.manualOverride = true
    m.settings.overrideProfile = index
    m.pendingStart = true
    saveSettings()
end sub

sub resumeSchedule()
    m.settings.manualOverride = false
    m.pendingStart = true
    saveSettings()
end sub

sub onRemoteRequest()
    if m.top.mode <> "player" then return
    action = RemoteAction(m.top.remoteRequest, m.settings)
    if action.ok then m.pendingRemote = action
    onScheduleTick()
end sub

sub onScheduleTick()
    if m.busy then return
    if m.pendingRemote <> invalid
        action = m.pendingRemote
        m.pendingRemote = invalid
        if action.action = "resume"
            resumeSchedule()
        else
            holdProfile(action.index)
        end if
        return
    end if
    if not m.playing or m.menu.visible then return
    if not m.settings.scheduleEnabled or m.settings.manualOverride then return
    target = clockTarget()
    if target <> m.activeProfile then activateProfile(target)
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
    m.slideTimer.duration = m.settings.profiles[m.activeProfile].seconds
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
        startLoop()
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
    m.scheduleTimer.control = "stop"
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
