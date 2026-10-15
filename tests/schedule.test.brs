sub Main()
    m.passed = 0
    m.failed = 0
    s = DefaultSettings()
    s.profiles[0].uuid = "open"
    s.profiles[0].schedule = "Sun 08:30, Sun 10:30"
    s.profiles[1].uuid = "closed"
    s.profiles[1].schedule = "Sun 09:00, Sun 11:00"
    s.scheduleEnabled = true
    Check(ParseSchedule("").ok, "blank clears schedule")
    Check(ParseSchedule("Daily 08:30").events.Count() = 7, "daily expands to every weekday")
    Check(ParseSchedule("sun 09:00, SUN 11:00").events.Count() = 2, "day names are case insensitive")
    Check(not ParseSchedule("Sun 24:00").ok, "24-hour overflow rejected")
    Check(not ParseSchedule("Sun 09:60").ok, "minute overflow rejected")
    Check(not ParseSchedule("Sun 9:00").ok, "ambiguous time rejected")
    Check(not ParseSchedule("Tomorrow 09:00").ok, "invalid weekday rejected")
    Check(not ParseSchedule("Sun 09:00,").ok, "trailing empty event rejected")
    Check(ScheduledProfile(s,0,8*60+45) = 0, "open before first service")
    Check(ScheduledProfile(s,0,9*60) = 1, "closes exactly at scheduled minute")
    Check(ScheduledProfile(s,0,10*60) = 1, "closed state persists between switches")
    Check(ScheduledProfile(s,0,10*60+30) = 0, "second service reopens check-in")
    Check(ScheduledProfile(s,0,11*60) = 1, "second service closes check-in")
    Check(ScheduledProfile(s,6,23*60) = 1, "latest weekly event carries across days")
    Check(ScheduledProfile(s,0,8*60) = 1, "week rollover uses prior week's latest switch")
    s.manualOverride = true
    s.overrideProfile = 0
    Check(ScheduledProfile(s,0,11*60) = 0, "manual override wins over current schedule")
    s.selected = 1
    Check(ScheduledProfile(s,0,11*60) = 0, "editing another profile does not change held override")
    s.manualOverride = false
    Check(ScheduledProfile(s,0,11*60) = 1, "resume immediately resolves current scheduled state")
    s.scheduleEnabled = false
    s.selected = 0
    Check(ScheduledProfile(s,0,11*60) = 0, "disabled schedule uses selected profile")
    s.profiles.Push(NewProfile("Lobby Welcome"))
    s.profiles[2].uuid = "welcome"
    s.profiles[2].schedule = "Daily 12:00"
    s.scheduleEnabled = true
    Check(ScheduledProfile(s,2,12*60) = 2, "arbitrary third profile and weekday supported")
    s.profiles[1].schedule = "Daily 12:00"
    Check(ScheduledProfile(s,2,12*60) = 1, "equal times resolve deterministically to lower profile")
    s.profiles[1].uuid = ""
    Check(ScheduledProfile(s,2,12*60) = 2, "unconfigured profile ignored by scheduler")
    Check(not RemoteAction({palAction:"switch",profile:"1"},s).ok, "remote control is opt-in")
    s.remoteEnabled = true
    Check(RemoteAction({palAction:"switch",profile:"3"},s).index = 2, "remote uses stable one-based profile numbers")
    Check(RemoteAction({palAction:"resume"},s).ok, "remote resume supported")
    Check(not RemoteAction({palAction:"switch",profile:"4"},s).ok, "unknown profile rejected")
    Check(not RemoteAction({palAction:"switch",profile:"0"},s).ok, "zero profile rejected")
    Check(not RemoteAction({palAction:"switch",profile:"1junk"},s).ok, "malformed remote profile rejected")
    Check(not RemoteAction({palAction:"refresh"},s).ok, "unknown remote action rejected")
    Check(not RemoteAction(invalid,s).ok, "invalid remote payload rejected")
    s.selected = 2
    restored = NormalizeSettings(ParseJson(FormatJson(s)))
    Check(restored.profiles.Count() = 3, "custom profiles survive restart")
    Check(restored.profiles[2].label = "Lobby Welcome", "custom names survive restart")
    Check(restored.profiles[2].schedule = "Daily 12:00", "switch times survive restart")
    Check(restored.remoteEnabled, "remote preference survives restart")
    copy = ProfileSettings(s,0)
    Check(s.selected = 2 and copy.selected = 0, "cache fetch selection does not mutate user settings")
    Check(ProfileCacheRoot("player",0) <> ProfileCacheRoot("player",1), "profiles have isolated cache slots")
    Check(ProfileCacheRoot("player",0) <> ProfileCacheRoot("screensaver",0), "apps retain separate cache namespaces")
    print "RESULT passed="; m.passed; " failed="; m.failed
end sub

sub Check(condition as boolean, description as string)
    if condition
        m.passed++
        print "PASS "; description
    else
        m.failed++
        print "FAIL "; description
    end if
end sub
