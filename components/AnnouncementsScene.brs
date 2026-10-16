sub init()
    m.top.backgroundColor = "0x000000FF"
    for each id in ["front", "back", "validator", "menu", "heading", "summary", "list", "status", "notice", "slideTimer", "loadTimer", "validateTimer", "noticeTimer", "heartbeat", "startup", "scheduleTimer", "slides", "dissolve", "fadeTrack", "pauseBadge", "description", "fadeTimer"]
        m[id] = m.top.FindNode(id)
    end for
    m.fadeTimer.ObserveField("fire", "onFadeTimeout")
    m.fadeClock = CreateObject("roTimespan")
    m.fadeRemaining = 0.35
    m.dissolve.ObserveField("state", "onDissolveState")
    m.slideClock = CreateObject("roTimespan")
    m.paused = false
    m.menuAutoPaused = false
    m.editProfile = 0
    m.addingPresentation = false
    m.pendingShowIndex = -1
    m.transitioning = false
    m.pendingReady = false
    m.pendingDeck = invalid
    m.remainingSeconds = 13
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
    m.demoMode = false
    m.backgroundRefresh = false
    m.refreshAttempts = {}
    m.startAfterRefresh = false
    m.startupRefreshing = false
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
    if m.playing and not m.backgroundRefresh then showNotice(m.worker.progress)
end sub

sub onResult()
    r = m.worker.result
    m.busy = false
    if not r.ok
        if r.action = "fetch" or r.action = "commit" then recordRefreshAttempt()
        if r.action = "commit" and m.candidate <> invalid
            rejectCandidate(r.error)
            return
        end if
        m.refreshQueue = []
        m.pendingShowIndex = -1
        m.startAfterRefresh = false
        m.startupRefreshing = false
        m.status.text = r.error
        if not m.backgroundRefresh then showNotice(r.error)
        if m.backgroundRefresh then print "PAL background refresh failed: "; r.error
        m.backgroundRefresh = false
        if m.isScreensaver and not m.playing then m.notice.visible = true
        return
    end if
    if r.action = "init"
        m.settings = r.settings
        m.decks = r.decks
        m.editProfile = m.settings.selected
        m.activeProfile = m.settings.selected
        m.deck = r.cached
        home()
        if m.isScreensaver and RefreshOrder(m.settings,m.settings.selected).Count() = 0
            startDemo()
            return
        end if
        target = clockTarget()
        if m.isScreensaver
            if profileReady(target)
                activateProfile(target)
            else
                m.startAfterRefresh = true
            end if
        end if
        m.refreshQueue = RefreshOrder(m.settings, target)
        if m.settings.baseUrl <> "" and m.refreshQueue.Count() > 0
            m.startupRefreshing = true
            nextProfile = m.refreshQueue.Shift()
            refreshProfile(nextProfile)
        else
            m.status.text = "Add a presentation, then choose Show now or Start slideshow."
        end if
    else if r.action = "save"
        showPage(m.savePage)
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
        if r.unchanged = true
            recordRefreshAttempt()
            m.decks[m.fetchIndex] = r.deck
            print "PAL refresh profile="; m.fetchIndex + 1; " unchanged"
            finishRefresh("Slides are already up to date.")
            return
        end if
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
        recordRefreshAttempt()
        m.decks[m.fetchIndex] = r.deck
        m.candidate = invalid
        applyToPlayback = not m.playing
        if IsMap(m.deck) then applyToPlayback = m.deck.identity = r.deck.identity
        if m.fetchIndex = m.activeProfile and applyToPlayback
            if m.backgroundRefresh and m.playing
                m.pendingDeck = r.deck
                ' A single-slide deck has no advance timer, so show its update once ready.
                if m.deck.files.Count() = 1 and not m.paused
                    m.deck = m.pendingDeck
                    m.pendingDeck = invalid
                    loadSlide(0)
                end if
            else if m.paused
                m.pendingDeck = r.deck
            else
                cancelTransition()
                m.deck = r.deck
                if m.playing
                    m.slideTimer.control = "stop"
                    m.loadTimer.control = "stop"
                    m.loading = false
                    m.back.uri = ""
                    loadSlide(0)
                end if
            end if
        end if
        print "PAL refresh profile="; m.fetchIndex + 1; " updated"
        if not m.playing and m.startAfterRefresh and profileReady(clockTarget())
            m.startAfterRefresh = false
            activateProfile(clockTarget())
        end if
        finishRefresh("Refresh complete. Other cached profiles are retained.")
    else if r.action = "discard"
        m.candidate = invalid
        m.startupRefreshing = false
        m.status.text = "Refresh cancelled: " + m.validationError + " Existing slideshow retained."
        if not m.backgroundRefresh then showNotice(m.status.text)
        recordRefreshAttempt()
        m.backgroundRefresh = false
    end if
end sub

sub finishRefresh(message as string)
    if m.refreshQueue.Count() > 0
        nextProfile = m.refreshQueue.Shift()
        refreshProfile(nextProfile)
    else
        m.startupRefreshing = false
        if m.backgroundRefresh
            m.status.text = message
        else
            showNotice(message)
        end if
        m.backgroundRefresh = false
        if m.pendingShowIndex >= 0
            index = m.pendingShowIndex
            m.pendingShowIndex = -1
            beginShowNow(index)
            return
        end if
        if m.startAfterRefresh
            m.startAfterRefresh = false
            startLoop()
        end if
        if m.menu.visible then updateSummary()
    end if
end sub

sub home()
    showPage("home")
end sub

sub showPage(page as string)
    if page = "configured"
        showConfigured()
        return
    end if
    spec = MenuPage(page, ProfileSettings(m.settings,m.editProfile), m.paused)
    m.page = page
    m.heading.text = spec.title
    m.description.text = spec.description
    m.actions = spec.actions
    if page = "home" and m.top.mode = "settings" then spec.labels[0] = "Preview slideshow"
    setList(spec.labels)
    updateSummary()
end sub

sub updateSummary()
    summaryIndex = m.editProfile
    if m.page <> "detail" and m.page <> "libraries" and m.page <> "presentations" and m.page <> "showMode"
        summaryIndex = m.settings.selected
        if m.playing then summaryIndex = m.activeProfile
    end if
    p = m.settings.profiles[summaryIndex]
    name = p.name
    if name = "" then name = "Choose a presentation to begin"
    cache = "Slides not downloaded yet"
    selectedDeck = m.decks[summaryIndex]
    if CacheMatches(selectedDeck, DeckIdentity(ProfileSettings(m.settings,summaryIndex)))
        count = selectedDeck.files.Count()
        cache = count.ToStr() + " slides ready"
        if count = 1 then cache = "1 slide - stays on screen"
    end if
    timing = p.seconds.ToStr() + " seconds per slide"
    state = "Ready"
    if m.playing then state = "Playing: " + m.settings.profiles[m.activeProfile].label
    if m.paused then state = "Paused"
    if m.settings.manualOverride
        held = true
        if m.settings.DoesExist("overrideUntil")
            if m.settings.overrideUntil > 0
                now = CreateObject("roDateTime")
                held = now.AsSeconds() < m.settings.overrideUntil
                if held then state = state + " / Until next switch"
            else
                state = state + " / Until resumed"
            end if
        else
            state = state + " / Until resumed"
        end if
    end if
    m.summary.text = p.label + Chr(10) + name + Chr(10) + cache + Chr(10) + timing + Chr(10) + "0.3-second dissolve" + Chr(10) + state
    if m.settings.remoteEnabled then m.summary.text = m.summary.text + Chr(10) + "Remote number: " + (summaryIndex + 1).ToStr()
    if m.page = "connection"
        address = m.settings.baseUrl
        if address = "" then address = "Address not set"
        m.summary.text = "ProPresenter" + Chr(10) + address + Chr(10) + Chr(10) + "Presentation" + Chr(10) + p.label
    end if
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
    m.description.text = "Select with OK. Press Back to return home."
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
    ' Startup checking must not prevent starting an already-cached presentation.
    if m.busy and m.startupRefreshing
        if m.page = "home" or m.page = "content"
            if m.actions[m.list.itemSelected] = "start"
                target = clockTarget()
                if profileReady(target)
                    activateProfile(target)
                else
                    m.startAfterRefresh = true
                    showNotice("Downloading the selected presentation. Playback will start when ready.")
                end if
                return
            end if
        end if
    end if
    if m.busy
        showNotice("Please wait for the current operation to finish.")
        return
    end if
    index = m.list.itemSelected
    if Left(m.page, 5) = "rule:"
        selectRuleItem(index)
        return
    end if
    if m.page = "intervalPicker"
        m.settings.profiles[m.editProfile].refreshMinutes = m.items[index].value
        saveSettings()
        return
    end if
    if m.page = "configured"
        item = m.items[index]
        if item.action = "edit"
            m.editProfile = item.profile
            showPage("detail")
        else if item.action = "add"
            if AvailableSlot(m.settings) < 0
                showNotice("Maximum eight presentations per TV. Remove one before adding another.")
            else
                m.addingPresentation = true
                browsePresentations()
            end if
        else
            refreshAll()
        end if
        return
    else if m.page = "showMode"
        showPresentation(m.editProfile,index = 0)
        return
    else if m.page = "libraries"
        if index >= m.items.Count() then return
        request({action: "presentations", settings: m.settings, library: m.items[index].name})
        m.status.text = "Reading presentations..."
        return
    else if m.page = "presentations"
        if index >= m.items.Count() then return
        selected = m.items[index]
        if m.addingPresentation
            slot = AvailableSlot(m.settings)
            if slot < 0 then return
            if slot = m.settings.profiles.Count()
                m.settings.profiles.Push(NewProfile(selected.name))
                m.decks.Push(invalid)
            end if
            m.editProfile = slot
            m.settings.profiles[slot] = NewProfile(Left(selected.name,40))
            m.addingPresentation = false
        end if
        p = m.settings.profiles[m.editProfile]
        p.uuid = selected.uuid
        p.name = selected.name
        ' Playback holds its current deck; edits are applied only by Show now or a switch.
        saveSettings()
        return
    end if
    action = m.actions[index]
    if Left(action, 5) = "page:"
        showPage(Mid(action, 6))
    else if action = "start"
        startLoop()
    else if action = "refresh"
        refreshDeck()
    else if action = "interval"
        items = []
        for each minutes in [0,1,5,10,15,30,60,120]
            items.Push({name:RefreshIntervalLabel(minutes),value:minutes})
        end for
        showItems("intervalPicker","Automatic refresh",items)
        m.description.text = "Checks this presentation in the background during playback, including the screensaver."

    else if action = "showNow"
        beginShowNow(m.editProfile)
    else if action = "remove"
        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title = "Remove " + m.settings.profiles[m.editProfile].label + "?"
        dialog.message = "Remove it and its switch times from this TV? The presentation in ProPresenter stays available."
        dialog.buttons = ["Remove from this TV","Cancel"]
        dialog.ObserveField("buttonSelected","onRemovePresentation")
        m.top.dialog = dialog
    else if action = "resume"
        resumeSchedule()
    else if action = "refreshAll"
        refreshAll()
    else if action = "rename"
        editValue("rename", "Presentation name", m.settings.profiles[m.editProfile].label)
    else if action = "schedule"
        showSwitchTimes()
    else if action = "scheduleEnabled"
        m.settings.scheduleEnabled = not m.settings.scheduleEnabled
        saveSettings()
    else if action = "remote"
        m.settings.remoteEnabled = not m.settings.remoteEnabled
        saveSettings()
    else if action = "address"
        editValue("address", "ProPresenter address (example: 192.168.1.50:50001)", m.settings.baseUrl)
    else if action = "browse"
        m.addingPresentation = false
        browsePresentations()
    else if action = "duration"
        editValue("duration", "Seconds per slide (1-3600)", m.settings.profiles[m.editProfile].seconds.ToStr())
    else if action = "demo"
        startDemo()
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
                showNotice("Use a presentation name of 1 to 40 characters.")
                return
            end if
            m.settings.profiles[m.editProfile].label = value
        else if m.editKind = "schedule"
            parsed = ParseSchedule(value)
            if not parsed.ok
                showNotice(parsed.error)
                return
            end if
            m.settings.profiles[m.editProfile].schedule = value
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
            m.settings.profiles[m.editProfile].seconds = Int(seconds)
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
    if m.demoMode
        showNotice("Leave the offline demo before changing saved settings.")
        return
    end if
    m.savePage = m.page
    if m.page = "presentations" then m.savePage = "detail"
    if m.page = "showMode" or m.page = "intervalPicker" then m.savePage = "detail"
    if Left(m.page,5) = "rule:" then m.savePage = "schedule"
    request({action: "save", settings: m.settings})
end sub

sub refreshDeck()
    refreshProfile(m.editProfile)
end sub

sub refreshAll()
    if m.busy then return
    m.refreshQueue = RefreshOrder(m.settings, m.settings.selected)
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
    recordRefreshAttempt()
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
    m.pendingShowIndex = -1
    m.startupRefreshing = false
    m.validationError = reason
    m.busy = false
    candidate = m.candidate
    m.candidate = invalid
    request({action: "discard", deck: candidate})
end sub

function clockTarget() as integer
    now = CreateObject("roDateTime")
    utcSeconds = now.AsSeconds()
    if m.settings.DoesExist("overrideUntil")
        if m.settings.overrideUntil > 0 and utcSeconds >= m.settings.overrideUntil
            m.settings.manualOverride = false
            m.settings.overrideUntil = 0
        end if
    end if
    now.ToLocalTime()
    return ScheduledProfile(m.settings, now.GetDayOfWeek(), now.GetHours() * 60 + now.GetMinutes(),utcSeconds)
end function

sub startLoop()
    if m.busy then return
    target = clockTarget()
    if m.settings.profiles[target].uuid = ""
        showNotice("Add a presentation before starting the slideshow.")
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
        showNotice("This presentation is not cached. Use Refresh all before switching.")
        return
    end if
    cancelTransition()
    m.paused = false
    m.menuAutoPaused = false
    m.pauseBadge.visible = false
    m.pendingDeck = invalid
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
        showNotice("Refresh all presentations first. The current presentation is unchanged.")
        return
    end if
    if not m.settings.scheduleEnabled then m.settings.selected = index
    m.settings.overrideUntil = 0
    m.settings.manualOverride = true
    m.settings.overrideProfile = index
    m.pendingStart = true
    saveSettings()
end sub

sub resumeSchedule()
    m.settings.manualOverride = false
    m.settings.overrideUntil = 0
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
        else if action.action = "refreshAll"
            refreshAll()
        else if action.action = "refresh"
            refreshProfile(action.index)
        else
            holdProfile(action.index)
        end if
        return
    end if
    if not m.playing or m.menu.visible or m.paused then return
    if not m.settings.scheduleEnabled
        onAutoRefresh()
        return
    end if
    target = clockTarget()
    if target <> m.activeProfile then activateProfile(target)
    onAutoRefresh()
end sub

sub stopLoop()
    cancelTransition()
    m.paused = false
    m.menuAutoPaused = false
    m.pauseBadge.visible = false
    m.pendingDeck = invalid
    m.playing = false
    m.loading = false
    m.slideTimer.control = "stop"
    m.loadTimer.control = "stop"
    m.back.uri = ""
    m.menu.visible = true
    if m.demoMode
        context = m.demoContext
        m.settings = context.settings
        m.decks = context.decks
        m.deck = context.deck
        m.editProfile = context.editProfile
        m.activeProfile = context.activeProfile
        m.demoMode = false
        m.demoContext = invalid
        m.front.uri = ""
    end if
    home()
end sub

sub loadSlide(index as integer)
    if not m.playing or m.deck = invalid then return
    cancelTransition()
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
        if m.paused and m.front.uri <> ""
            m.pendingReady = true
        else
            beginTransition()
        end if
    else if m.back.loadStatus = "failed"
        slideFailed()
    end if
end sub

sub beginTransition()
    m.pendingReady = false
    if m.front.uri = ""
        finishTransition()
        return
    end if
    ' Put the incoming image above the outgoing image, then fade only the incoming
    ' opacity. Fading both images would darken their composite halfway through.
    m.slides.RemoveChild(m.back)
    m.slides.AppendChild(m.back)
    m.back.opacity = 0
    m.fadeTrack.fieldToInterp = m.back.id + ".opacity"
    m.transitioning = true
    m.dissolve.control = "start"
    m.fadeRemaining = 0.35
    m.fadeClock.Mark()
    m.fadeTimer.duration = m.fadeRemaining
    m.fadeTimer.control = "start"
end sub

sub onDissolveState()
    if m.transitioning and m.dissolve.state = "stopped" then finishTransition()
end sub

sub finishTransition()
    m.transitioning = false
    m.fadeTimer.control = "stop"
    m.dissolve.control = "stop"
    m.back.opacity = 1
    m.front.opacity = 0
    m.front.uri = ""
    previous = m.front
    m.front = m.back
    m.back = previous
    if m.nextIndex = 0 and m.index >= 0 then m.cycles++
    m.index = m.nextIndex
    print "PAL slide="; m.index + 1; "/"; m.deck.files.Count(); " loops="; m.cycles
    scheduleSlide()
end sub

sub cancelTransition()
    m.transitioning = false
    m.fadeTimer.control = "stop"
    m.pendingReady = false
    m.dissolve.control = "stop"
    m.front.opacity = 1
    m.back.opacity = 0
end sub

sub togglePause()
    if not m.playing
        showNotice("Start the slideshow first.")
        return
    end if
    if not m.paused
        m.paused = true
        m.remainingSeconds = m.slideTimer.duration - m.slideClock.TotalMilliseconds() / 1000.0
        if m.remainingSeconds < 0.1 then m.remainingSeconds = 0.1
        m.slideTimer.control = "stop"
        if m.transitioning
            m.fadeRemaining = m.fadeTimer.duration - m.fadeClock.TotalMilliseconds() / 1000.0
            if m.fadeRemaining < 0.02 then m.fadeRemaining = 0.02
            m.fadeTimer.control = "stop"
            m.dissolve.control = "pause"
        end if
        m.pauseBadge.visible = true
    else
        m.paused = false
        m.pauseBadge.visible = false
        if m.pendingDeck <> invalid
            cancelTransition()
            m.deck = m.pendingDeck
            m.pendingDeck = invalid
            m.loadTimer.control = "stop"
            m.loading = false
            loadSlide(0)
        else if m.pendingReady
            beginTransition()
        else if m.transitioning
            m.dissolve.control = "resume"
            m.fadeClock.Mark()
            m.fadeTimer.duration = m.fadeRemaining
            m.fadeTimer.control = "start"
        else if not m.loading
            m.slideTimer.duration = m.remainingSeconds
            m.slideClock.Mark()
            if m.deck.files.Count() > 1 then m.slideTimer.control = "start"
        end if
    end if
    if m.menu.visible
        if m.page = "home" or m.page = "detail" or m.page = "schedule" or m.page = "connection" then showPage(m.page)
    end if
end sub

sub onFadeTimeout()
    if m.transitioning and not m.paused then finishTransition()
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
    m.remainingSeconds = m.slideTimer.duration
    m.slideClock.Mark()
    if m.playing and not m.paused and m.deck.files.Count() > 1 then m.slideTimer.control = "start"
end sub

sub onSlideTimer()
    if m.paused or not m.playing then return
    if m.pendingDeck <> invalid
        m.deck = m.pendingDeck
        m.pendingDeck = invalid
        loadSlide(0)
        return
    end if
    if m.deck.files.Count() <= 1 then return
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
        ' Recovery retry when there are no playable slides; periodic checks use onAutoRefresh.
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
    cancelTransition()
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

sub closeControls()
    m.menu.visible = false
    if m.menuAutoPaused and m.paused then togglePause()
    m.menuAutoPaused = false
    m.top.SetFocus(true)
end sub

sub showSwitchTimes()
    m.timeline = ScheduleTimeline(m.settings)
    items = []
    for each row in m.timeline
        items.Push({name:ScheduleEntryLabel(row.rule) + " > " + m.settings.profiles[row.profile].label})
    end for
    items.Push({name:"Add switch time"})
    showItems("rule:list", "Schedule switch times", items)
    m.description.text = "Each time chooses what this TV shows. Select a switch to edit or delete it."
end sub

sub showRuleEditor()
    e = m.ruleDraft
    hour = e.hour mod 12
    if hour = 0 then hour = 12
    period = "AM"
    if e.hour >= 12 then period = "PM"
    day = e.day
    if LCase(day) = "daily" then day = "Every day"
    items = [{name:"Show: " + m.settings.profiles[e.profile].label},{name:"Day: " + day}, {name:"Hour: " + hour.ToStr()}, {name:"Minute: " + TwoDigits(e.minute)}, {name:"AM / PM: " + period}, {name:"Save switch time"}]
    if m.ruleIndex >= 0 then items.Push({name:"Delete switch time"})
    showItems("rule:edit", "Schedule switch", items)
    m.description.text = "Choose a presentation, day and time. Save when finished. Back cancels this edit."
    m.status.text = ScheduleEntryLabel(e) + " — Roku local time"
end sub

sub selectRuleItem(index as integer)
    if m.page = "rule:list"
        m.ruleIndex = -1
        m.ruleSourceProfile = -1
        target = -1
        for i = 0 to m.settings.profiles.Count() - 1
            if target < 0 and m.settings.profiles[i].uuid <> "" then target = i
        end for
        if target < 0
            showNotice("Add a presentation before creating a schedule.")
            return
        end if
        m.ruleDraft = {day:"Sun", hour:9, minute:0,profile:target}
        if index < m.timeline.Count()
            row = m.timeline[index]
            e = row.rule
            m.ruleSourceProfile = row.profile
            m.ruleIndex = row.entry
            m.ruleDraft = {day:e.day,hour:e.hour,minute:e.minute,profile:row.profile}
        end if
        showRuleEditor()
    else if m.page = "rule:edit"
        if index = 5 or index = 6
            if not ApplyScheduleEdit(m.settings,m.ruleSourceProfile,m.ruleIndex,m.ruleDraft,index = 6)
                showNotice("Maximum 16 switch times per presentation. Remove a time first.")
                return
            end if
            saveSettings()
        else
            items = []
            field = "profile"
            title = "Choose what to show"
            if index = 0
                for i = 0 to m.settings.profiles.Count() - 1
                    if m.settings.profiles[i].uuid <> "" then items.Push({name:m.settings.profiles[i].label,value:i})
                end for
            else if index = 1
                field = "day"
                title = "Choose day"
                for each day in ["Sun","Mon","Tue","Wed","Thu","Fri","Sat","Daily"]
                    label = day
                    if day = "Daily" then label = "Every day"
                    items.Push({name:label,value:day})
                end for
            else if index = 2
                field = "hour"
                title = "Choose hour"
                for hour = 1 to 12
                    items.Push({name:hour.ToStr(),value:hour mod 12})
                end for
            else if index = 3
                field = "minute"
                title = "Choose minute"
                for minute = 0 to 59
                    items.Push({name:TwoDigits(minute),value:minute})
                end for
            else
                field = "period"
                title = "Choose AM or PM"
                items = [{name:"AM",value:0},{name:"PM",value:12}]
            end if
            showItems("rule:" + field, title, items)
            m.description.text = "Choose with OK. Back keeps the current value."
            if field = "minute" then m.description.text = "Up/Down: 1 minute. Left/Right: 10 minutes. OK: choose."
            current = m.ruleDraft[field]
            if field = "hour" then current = m.ruleDraft.hour mod 12
            if field = "period" then current = Int(m.ruleDraft.hour / 12) * 12
            for i = 0 to items.Count() - 1
                if items[i].value = current then m.list.jumpToItem = i
            end for
        end if
    else
        if index >= m.items.Count() then return
        value = m.items[index].value
        field = Mid(m.page,6)
        if field = "hour"
            m.ruleDraft.hour = value + Int(m.ruleDraft.hour / 12) * 12
        else if field = "period"
            m.ruleDraft.hour = (m.ruleDraft.hour mod 12) + value
        else
            m.ruleDraft[field] = value
        end if
        showRuleEditor()
        focus = 0
        if field = "day" then focus = 1
        if field = "hour" then focus = 2
        if field = "minute" then focus = 3
        if field = "period" then focus = 4
        m.list.jumpToItem = focus
    end if
end sub

sub showConfigured()
    items = []
    for i = 0 to m.settings.profiles.Count() - 1
        p = m.settings.profiles[i]
        if p.uuid <> ""
            label = p.label
            if m.playing and i = m.activeProfile then label = label + " — Showing now"
            if not m.playing and i = m.settings.selected then label = label + " — Default"
            items.Push({name:label,action:"edit",profile:i})
        end if
    end for
    items.Push({name:"Add presentation",action:"add"})
    items.Push({name:"Refresh all",action:"refreshAll"})
    showItems("configured","Presentations",items)
    m.description.text = "Presentations added to this TV. Select one to edit its settings or choose Show now."
    updateSummary()
end sub

sub browsePresentations()
    if m.settings.baseUrl = ""
        showNotice("Set the ProPresenter computer address in Connection & TV settings first.")
        return
    end if
    m.status.text = "Reading libraries..."
    request({action:"libraries",settings:m.settings})
end sub

sub showPresentation(index as integer, untilNext as boolean)
    if not profileReady(index)
        showNotice("Refresh this presentation's slides before choosing Show now.")
        return
    end if
    m.settings.overrideUntil = 0
    if m.settings.scheduleEnabled
        if untilNext
            now = CreateObject("roDateTime")
            utcSeconds = now.AsSeconds()
            now.ToLocalTime()
            delay = NextSwitchDelay(m.settings,now.GetDayOfWeek(),now.GetHours() * 60 + now.GetMinutes())
            if delay = 0
                showNotice("No scheduled switches yet. Add one or choose Until I resume the schedule.")
                return
            end if
            m.settings.overrideUntil = utcSeconds + delay * 60 - now.GetSeconds()
        end if
        m.settings.manualOverride = true
        m.settings.overrideProfile = index
    else
        m.settings.selected = index
        m.settings.manualOverride = false
    end if
    m.pendingStart = true
    saveSettings()
end sub

sub onRemovePresentation()
    dialog = m.top.dialog
    if dialog.buttonSelected = 0
        index = m.editProfile
        if m.playing and m.activeProfile = index then stopLoop()
        m.settings.profiles[index] = NewProfile("Presentation")
        m.decks[index] = invalid
        if m.settings.overrideProfile = index
            m.settings.manualOverride = false
            m.settings.overrideUntil = 0
        end if
        if m.settings.selected = index
            m.settings.selected = 0
            for i = 0 to m.settings.profiles.Count() - 1
                if m.settings.profiles[i].uuid <> ""
                    m.settings.selected = i
                    exit for
                end if
            end for
        end if
        m.editProfile = m.settings.selected
        m.page = "configured"
        dialog.close = true
        saveSettings()
    else
        dialog.close = true
        m.list.SetFocus(true)
    end if
end sub

sub beginShowNow(index as integer)
    if not profileReady(index)
        m.pendingShowIndex = index
        refreshProfile(index)
    else if m.settings.scheduleEnabled
        showItems("showMode","Show " + m.settings.profiles[index].label,[{name:"Until the next scheduled switch"},{name:"Until I resume the schedule"}])
    else
        showPresentation(index,false)
    end if
end sub

sub recordRefreshAttempt()
    if m.started = invalid then return
    m.refreshAttempts[m.fetchIndex.ToStr()] = m.started.TotalMilliseconds()
end sub

sub onAutoRefresh()
    if m.busy or m.lowMemory or not m.playing or m.menu.visible or m.paused then return
    index = DueRefresh(m.settings,m.started.TotalMilliseconds(),m.refreshAttempts,m.activeProfile)
    if index < 0 then return
    m.backgroundRefresh = true
    refreshProfile(index)
end sub

sub startDemo()
    if m.busy or m.demoMode then return
    m.demoContext = {settings:m.settings,decks:m.decks,deck:m.deck,editProfile:m.editProfile,activeProfile:m.activeProfile}
    m.settings = DemoSettings()
    m.decks = [DemoDeck(),invalid]
    m.editProfile = 0
    m.demoMode = true
    activateProfile(0)
end sub
