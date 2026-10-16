sub ShowProAnnouncementLooper(mode as string, input = invalid as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    sceneType = "ControlsScene"
    if mode = "screensaver" then sceneType = "AnnouncementsScene"
    scene = screen.CreateScene(sceneType)
    scene.mode = mode
    scene.ObserveField("exitRequested", port)
    monitor = CreateObject("roAppMemoryMonitor")
    if monitor <> invalid
        monitor.SetMessagePort(port)
        monitor.EnableMemoryWarningEvent(true)
    end if
    if input <> invalid then input.SetMessagePort(port)
    screen.Show()
    while true
        msg = Wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.IsScreenClosed() then exit while
        else if type(msg) = "roInputEvent"
            if msg.IsInput() then scene.remoteRequest = msg.GetInfo()
        else if type(msg) = "roSGNodeEvent"
            if msg.GetField() = "exitRequested" and msg.GetData() = true then exit while
        else if type(msg) = "roAppMemoryNotificationEvent"
            info = msg.GetInfo()
            pct = info.Lookup("memoryUsagePercent")
            if pct <> invalid then scene.memoryPercent = pct
        end if
    end while
    scene.shuttingDown = true
    screen.Close()
end sub
