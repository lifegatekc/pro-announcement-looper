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
    print "RESULT passed="; m.passed; " failed="; m.failed
end sub

sub SetupScene()
    m.settings = DefaultSettings()
    m.top = {
        mode:"player", memoryPercent:0,
        RemoveChild: sub(child)
        end sub,
        CreateChild: function(kind)
            return FakeWorker()
        end function
    }
    m.front = {uri:"cachefs:/old/0.jpg",opacity:1,loadStatus:"ready"}
    m.back = {uri:"",opacity:0,loadStatus:"none"}
    m.validator = {uri:"",loadStatus:"none"}
    m.menu = {visible:false}
    m.status = {text:""}
    m.notice = {text:"",visible:false}
    m.slideTimer = {control:"start",duration:13}
    m.loadTimer = {control:"stop"}
    m.validateTimer = {control:"stop"}
    m.noticeTimer = {control:"stop"}
    m.worker = FakeWorker()
    m.deck = {identity:"old",generation:"cachefs:/old/",files:["cachefs:/old/0.jpg","cachefs:/old/1.jpg"]}
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
