sub Main()
    m.passed = 0
    m.failed = 0
    SetupScene()
    oldDeck = m.deck
    m.worker.result = {ok:false,action:"fetch",error:"Connection failed"}
    onResult()
    Check(m.deck.generation = oldDeck.generation, "failed refresh retains active deck")
    Check(m.playing, "failed refresh keeps playback active")
    Check(m.front.uri = "cachefs:/old/0.jpg", "failed refresh keeps displayed image")
    Check(not m.busy, "failed refresh releases busy state")

    m.worker.result = {ok:true,action:"fetch",deck:{identity:"new",generation:"cachefs:/new/",files:["cachefs:/new/0.jpg","cachefs:/new/1.jpg"]}}
    onResult()
    Check(m.deck.generation = oldDeck.generation, "download does not prematurely replace active deck")
    Check(m.validating and m.busy, "download enters image validation")
    Check(m.validator.uri = "cachefs:/new/0.jpg", "first candidate image is decoded")
    m.validator.loadStatus = "ready"
    onValidated()
    Check(m.validationIndex = 1, "validation advances through each image")
    Check(m.deck.generation = oldDeck.generation, "partial validation preserves active deck")
    onValidated()
    Check(m.worker.request.action = "commit", "all decoded images request cache commit")
    Check(not m.validating, "validation ends before asynchronous commit")
    candidate = m.candidate
    m.worker.result = {ok:true,action:"commit",deck:candidate}
    onResult()
    Check(m.deck.generation = "cachefs:/new/", "successful commit promotes replacement deck")
    Check(m.front.uri = "cachefs:/old/0.jpg", "old image remains until replacement is ready")
    Check(m.back.uri = "cachefs:/new/0.jpg", "replacement image loads locally")
    m.back.loadStatus = "ready"
    onPoster()
    if m.transitioning then finishTransition()
    Check(m.front.uri = "cachefs:/new/0.jpg", "ready replacement becomes visible")
    Check(m.back.uri = "", "old decoded image released")
    Check(m.slideTimer.duration = 13, "slide duration starts after image is ready")
    Check(m.slideTimer.control = "start", "slideshow keeps running after refresh")

    SetupScene()
    m.candidate = {generation:"cachefs:/bad/",files:["cachefs:/bad/0.jpg"]}
    m.validating = true
    m.validator.loadStatus = "failed"
    onValidated()
    Check(m.worker.request.action = "discard", "corrupt candidate is discarded")
    Check(m.deck.generation = "cachefs:/old/", "corrupt candidate leaves active deck intact")
    Check(m.playing, "corrupt candidate does not stop playback")

    SetupScene()
    m.loading = true
    m.nextIndex = 1
    slideFailed()
    Check(m.front.uri = "cachefs:/old/0.jpg", "missing cached slide retains last displayed image")
    Check(m.slideTimer.control = "start", "missing slide retries on next regular interval")
    Check(m.index = 1, "missing slide is skipped")

    SetupScene()
    m.candidate = {generation:"cachefs:/new/",files:["cachefs:/new/0.jpg"]}
    m.validating = false
    m.busy = true
    m.top.memoryPercent = 85
    onMemory()
    Check(m.worker.request = invalid, "memory alert does not race an in-flight commit")
    Check(m.busy, "memory alert preserves in-flight worker state")
    SetupScene()
    m.cacheFs = {Exists: function(path)
        return true
    end function}
    m.settings.profiles[0].uuid = "old"
    m.deck.identity = "|old"
    m.settings.profiles[1].uuid = "other"
    m.decks[1] = {identity:"|other",generation:"cachefs:/other/",files:["cachefs:/other/0.jpg"]}
    m.busy = false
    holdProfile(1)
    Check(m.settings.manualOverride, "manual switch enables sticky override")
    Check(m.settings.overrideProfile = 1, "override targets selected profile")
    Check(m.worker.request.action = "save", "manual hold persists for screensaver takeover")
    Check(m.pendingStart, "manual switch waits for settings save before playback")

    SetupScene()
    m.cacheFs = {Exists: function(path)
        return false
    end function}
    m.busy = false
    holdProfile(1)
    Check(not m.settings.manualOverride, "missing cache does not establish a false override")
    Check(m.deck.generation = "cachefs:/old/", "missing target keeps current deck")
    Check(m.worker.request = invalid, "missing target does not trigger network fetch")

    SetupScene()
    m.settings.manualOverride = true
    m.busy = false
    resumeSchedule()
    Check(not m.settings.manualOverride, "resume clears sticky hold")
    Check(m.worker.request.action = "save", "resume persists the cleared override")

    SetupScene()
    m.pendingRemote = {action:"resume"}
    onScheduleTick()
    Check(m.pendingRemote <> invalid, "remote command waits while refresh is busy")
    SetupScene()
    m.page = "home"
    m.settings.profiles[0].uuid = "old"
    m.deck.identity = "|old"
    m.deck.cachedAt = "test"
    m.loading = true
    m.busy = false
    Check(onKeyEvent("back", true), "Back is handled during full-screen playback")
    Check(not m.playing, "Back stops the slideshow")
    Check(m.menu.visible, "Back returns to settings with a valid cached deck")
    Check(m.slideTimer.control = "stop", "Back cancels automatic advancement")

    SetupScene()
    m.index = m.deck.files.Count() - 1
    onSlideTimer()
    Check(m.nextIndex = 0, "last slide wraps to first slide")
    m.back.loadStatus = "ready"
    onPoster()
    if m.transitioning then finishTransition()
    Check(m.index = 0 and m.cycles = 1, "wrap records a completed loop")
    Check(m.slideTimer.control = "start", "wrapped slide schedules another advance")
    SetupScene()
    m.page = "home"
    Check(onKeyEvent("play", true), "Play/Pause key is handled")
    Check(m.paused and m.pauseBadge.visible, "Pause holds slide and displays indicator")
    Check(m.slideTimer.control = "stop", "Pause stops slide timer")
    Check(m.remainingSeconds = 9, "Pause preserves remaining slide time")
    onSlideTimer()
    Check(not m.loading, "stale timer cannot advance while paused")
    onKeyEvent("play", true)
    Check(not m.paused and not m.pauseBadge.visible, "Play resumes and clears indicator")
    Check(m.slideTimer.control = "start" and m.slideTimer.duration = 9, "Play resumes remaining interval")

    SetupScene()
    m.loading = true
    m.nextIndex = 1
    m.back.uri = "cachefs:/old/1.jpg"
    m.back.loadStatus = "ready"
    onPoster()
    Check(m.transitioning, "ready incoming image starts dissolve")
    Check(m.front.uri = "cachefs:/old/0.jpg" and m.front.opacity = 1, "outgoing image stays opaque during dissolve")
    Check(m.back.opacity = 0 and m.fadeTrack.fieldToInterp = "back.opacity", "dissolve targets incoming image opacity")
    Check(m.dissolve.control = "start", "dissolve animation starts")
    togglePause()
    Check(m.dissolve.control = "pause", "Pause suspends in-progress dissolve")
    togglePause()
    Check(m.dissolve.control = "resume", "Play resumes in-progress dissolve")
    m.dissolve.state = "stopped"
    onDissolveState()
    Check(not m.transitioning and m.front.uri = "cachefs:/old/1.jpg", "completed dissolve promotes incoming image")
    Check(m.back.uri = "", "completed dissolve releases outgoing image")

    SetupScene()
    m.paused = true
    m.worker.result = {ok:true,action:"commit",deck:{generation:"cachefs:/refreshed/",files:["cachefs:/refreshed/0.jpg"]}}
    onResult()
    Check(m.deck.generation = "cachefs:/old/" and m.pendingDeck <> invalid, "refresh while paused defers visible deck replacement")
    Check(m.front.uri = "cachefs:/old/0.jpg", "refresh while paused retains displayed slide")
    togglePause()
    Check(m.pendingDeck = invalid and m.deck.generation = "cachefs:/refreshed/", "Play applies a deferred refresh")

    SetupScene()
    m.paused = true
    m.loading = true
    m.nextIndex = 1
    m.back.uri = "cachefs:/old/1.jpg"
    m.back.loadStatus = "ready"
    onPoster()
    Check(m.pendingReady and not m.transitioning, "image finishing during pause waits for Play")
    togglePause()
    Check(m.transitioning and not m.pendingReady, "Play reveals image loaded during pause")
    stopLoop()
    Check(not m.paused and not m.transitioning, "Back cleanup cancels pause and dissolve")
    SetupScene()
    m.deck.files = ["cachefs:/old/0.jpg"]
    scheduleSlide()
    Check(m.slideTimer.control = "stop", "one-slide deck has no advance timer")
    onSlideTimer()
    Check(not m.loading, "one-slide deck ignores stale advance events")
    m.paused = true
    togglePause()
    Check(m.slideTimer.control = "stop", "resuming one slide does not restart looping")
    Check(onKeyEvent("right",true) and not m.loading, "manual next does not dissolve a single slide into itself")

    SetupScene()
    m.loading = true
    m.nextIndex = 1
    m.back.uri = "cachefs:/old/1.jpg"
    m.back.loadStatus = "ready"
    onPoster()
    Check(m.fadeTimer.control = "start", "dissolve arms independent completion fallback")
    onFadeTimeout()
    Check(not m.transitioning and m.index = 1, "missing animation event cannot stall playback")
    Check(m.slideTimer.control = "start", "fallback schedules next slide")
    Check(m.fadeTimer.control = "stop", "completion disarms fallback")

    SetupScene()
    m.loading = true
    m.nextIndex = 1
    m.back.uri = "cachefs:/old/1.jpg"
    m.back.loadStatus = "ready"
    onPoster()
    togglePause()
    onFadeTimeout()
    Check(m.transitioning and m.index = 0, "stale fallback cannot complete paused dissolve")
    togglePause()
    Check(m.fadeTimer.control = "start", "Play re-arms paused dissolve fallback")

    SetupScene()
    showPage("profiles")
    Check(m.page = "profiles" and m.heading.text = "Profiles & timing", "profile settings have a dedicated page")
    Check(m.actions.Count() = 5, "profile page fits without scrolling")
    showPage("home")
    Check(m.actions.Count() = 5, "home contains only start and four settings groups")
    SetupScene()
    m.busy = false
    m.paused = true
    m.settings.profiles[0].uuid = "old"
    m.deck.identity = "|old"
    activateProfile(0)
    Check(m.playing and not m.paused and m.loading, "Start automatically begins loading without Play")
    m.back.loadStatus = "ready"
    onPoster()
    if m.transitioning then finishTransition()
    Check(m.slideTimer.control = "start", "Start automatically schedules progression without Play")
    m.page = "playback"
    Check(onKeyEvent("back",true) and not m.playing and m.menu.visible, "Back stops full-screen playback started from a subpage")
    SetupScene()
    m.busy = false
    m.settings.profiles[0].uuid = "old"
    m.deck.identity = "|old"
    activateProfile(0)
    Check(not onKeyEvent("OK",true), "bubbling Start OK is not a playback shortcut")
    Check(not m.paused and not m.pauseBadge.visible, "Start OK cannot immediately pause slideshow")
    print "RESULT passed="; m.passed; " failed="; m.failed
end sub

sub SetupScene()
    m.settings = DefaultSettings()
    m.top = {
        mode:"player", memoryPercent:0,
        SetFocus: sub(focused)
        end sub,
        RemoveChild: sub(child)
        end sub,
        CreateChild: function(kind)
            return FakeWorker()
        end function
    }
    m.paused = false
    m.transitioning = false
    m.pendingReady = false
    m.pendingDeck = invalid
    m.remainingSeconds = 13
    m.pauseBadge = {visible:false}
    m.dissolve = {control:"stop",state:"stopped"}
    m.fadeTrack = {fieldToInterp:""}
    m.fadeTimer = {control:"stop",duration:0.35}
    m.fadeClock = {Mark: sub()
    end sub, TotalMilliseconds: function()
        return 100
    end function}
    m.slides = {RemoveChild: sub(child)
    end sub, AppendChild: sub(child)
    end sub}
    m.slideClock = {Mark: sub()
    end sub, TotalMilliseconds: function()
        return 4000
    end function}
    m.front = {id:"front",uri:"cachefs:/old/0.jpg",opacity:1,loadStatus:"ready"}
    m.back = {id:"back",uri:"",opacity:0,loadStatus:"none"}
    m.validator = {uri:"",loadStatus:"none"}
    m.menu = {visible:false}
    m.heading = {text:""}
    m.description = {text:""}
    m.summary = {text:""}
    m.list = {content:invalid,jumpToItem:0,SetFocus: sub(focused)
    end sub}
    m.status = {text:""}
    m.notice = {text:"",visible:false}
    m.slideTimer = {control:"start",duration:13}
    m.loadTimer = {control:"stop"}
    m.validateTimer = {control:"stop"}
    m.noticeTimer = {control:"stop"}
    m.worker = FakeWorker()
    m.deck = {identity:"old",generation:"cachefs:/old/",files:["cachefs:/old/0.jpg","cachefs:/old/1.jpg"]}
    m.decks = [m.deck, invalid]
    m.fetchIndex = 0
    m.activeProfile = 0
    m.refreshQueue = []
    m.pendingRemote = invalid
    m.pendingStart = false
    m.candidate = invalid
    m.validating = false
    m.playing = true
    m.loading = false
    m.busy = true
    m.isScreensaver = false
    m.startAfterRefresh = false
    m.lowMemory = false
    m.page = "controls"
    m.index = 0
    m.cycles = 0
end sub

function FakeWorker() as object
    return {
        result:invalid, request:invalid, control:"STOP",
        ObserveField: sub(field, callback)
        end sub,
        UnobserveField: sub(field)
        end sub
    }
end function

sub Check(condition as boolean, description as string)
    if condition
        m.passed++
        print "PASS "; description
    else
        m.failed++
        print "FAIL "; description
    end if
end sub
