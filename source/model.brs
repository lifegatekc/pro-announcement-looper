' Pure data helpers: shared by the network worker, UI, and executable unit tests.
function IsMap(value as dynamic) as boolean
    return type(value) = "roAssociativeArray"
end function

function IsList(value as dynamic) as boolean
    return type(value) = "roArray"
end function

function SafeText(value as dynamic, fallback = "" as string) as string
    if type(value) = "roString" or type(value) = "String" then return value
    return fallback
end function

function NewProfile(label as string) as object
    return {label: label, uuid: "", name: "", seconds: 13, schedule: ""}
end function

function DefaultSettings() as object
    return {baseUrl: "", selected: 0, scheduleEnabled: false, manualOverride: false, overrideProfile: 0, remoteEnabled: false, profiles: [NewProfile("Main Service"), NewProfile("Youth Service")]}
end function

function NormalizeSettings(raw as dynamic) as object
    result = DefaultSettings()
    if not IsMap(raw) then return result
    result.baseUrl = SafeText(raw.baseUrl)
    result.scheduleEnabled = raw.scheduleEnabled = true
    result.manualOverride = raw.manualOverride = true
    result.remoteEnabled = raw.remoteEnabled = true
    if not IsList(raw.profiles) then return result
    count = raw.profiles.Count()
    if count > 8 then count = 8
    for i = 0 to count - 1
        if i >= result.profiles.Count() then result.profiles.Push(NewProfile("Profile " + (i + 1).ToStr()))
        p = raw.profiles[i]
        if IsMap(p)
            target = result.profiles[i]
            label = SafeText(p.label).Trim()
            if label <> "" then target.label = Left(label, 40)
            target.uuid = SafeText(p.uuid)
            target.name = SafeText(p.name)
            target.schedule = SafeText(p.schedule)
            if not ParseSchedule(target.schedule).ok then target.schedule = ""
            seconds = Val(SafeText(p.seconds, "13"))
            if type(p.seconds) = "Integer" or type(p.seconds) = "roInt" then seconds = p.seconds
            if seconds >= 1 and seconds <= 3600 then target.seconds = Int(seconds)
        end if
    end for
    if type(raw.selected) = "Integer" or type(raw.selected) = "roInt"
        if raw.selected >= 0 and raw.selected < result.profiles.Count() then result.selected = raw.selected
    end if
    if type(raw.overrideProfile) = "Integer" or type(raw.overrideProfile) = "roInt"
        if raw.overrideProfile >= 0 and raw.overrideProfile < result.profiles.Count() then result.overrideProfile = raw.overrideProfile
    end if
    return result
end function

' Recurring local wall-clock switches, e.g. "Sun 09:00, Sun 11:00" or "Daily 08:30".
function ParseSchedule(text as string) as object
    events = []
    if text.Trim() = "" then return {ok: true, events: events}
    parts = text.Split(",")
    if parts.Count() > 16 then return {ok: false, error: "Maximum 16 switch times per profile."}
    pattern = CreateObject("roRegex", "^(Sun|Mon|Tue|Wed|Thu|Fri|Sat|Daily) ([01][0-9]|2[0-3]):[0-5][0-9]$", "i")
    days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    for each part in parts
        part = part.Trim()
        if not pattern.IsMatch(part) then return {ok: false, error: "Use Sun 09:00, Sun 11:00 or Daily 08:30 (24-hour time). Blank removes switches."}
        words = part.Split(" ")
        minute = Val(Left(words[1], 2)) * 60 + Val(Right(words[1], 2))
        for day = 0 to 6
            if LCase(words[0]) = "daily" or LCase(words[0]) = days[day] then events.Push(day * 1440 + minute)
        end for
    end for
    return {ok: true, events: events}
end function

function ScheduledProfile(settings as object, day as integer, minute as integer) as integer
    if settings.manualOverride then return settings.overrideProfile
    if not settings.scheduleEnabled then return settings.selected
    bestAge = 10081
    target = settings.selected
    now = day * 1440 + minute
    for i = 0 to settings.profiles.Count() - 1
        p = settings.profiles[i]
        rules = ParseSchedule(SafeText(p.schedule))
        if rules.ok and SafeText(p.uuid) <> ""
            for each eventMinute in rules.events
                age = (now - eventMinute + 10080) mod 10080
                ' Equal times resolve to the lower profile number.
                if age < bestAge
                    bestAge = age
                    target = i
                end if
            end for
        end if
    end for
    return target
end function

function ProfileSettings(settings as object, index as integer) as object
    copy = ParseJson(FormatJson(settings))
    copy.selected = index
    return copy
end function

function ProfileCacheRoot(mode as string, index as integer) as string
    return CacheRoot(mode) + "profile-" + index.ToStr() + "/"
end function

function RemoteAction(info as dynamic, settings as object) as object
    if not settings.remoteEnabled then return {ok: false}
    if not IsMap(info) then return {ok: false}
    action = SafeText(info.palAction)
    if action = "resume" then return {ok: true, action: action}
    if action = "switch"
        number = SafeText(info.profile)
        pattern = CreateObject("roRegex", "^[1-8]$", "")
        if pattern.IsMatch(number)
            index = Val(number) - 1
            if index < settings.profiles.Count() then return {ok: true, action: action, index: Int(index)}
        end if
    end if
    return {ok: false}
end function

function NormalizeBaseUrl(raw as string) as string
    value = raw.Trim()
    if value = "" then return ""
    if Instr(1, value, "://") = 0 then value = "http://" + value
    while Right(value, 1) = "/"
        value = Left(value, Len(value) - 1)
    end while
    ' Permit a host and optional port only; do not accept arbitrary paths or credentials.
    pattern = CreateObject("roRegex", "^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$", "i")
    if not pattern.IsMatch(value) then return ""
    authority = Mid(value, Instr(1, value, "://") + 3)
    colon = Instr(1, authority, ":")
    if colon = 0
        value = value + ":50001"
    else
        port = Val(Mid(authority, colon + 1))
        if port < 1 or port > 65535 then return ""
    end if
    return value
end function

function UrlPart(value as string) as string
    transfer = CreateObject("roUrlTransfer")
    return transfer.Escape(value)
end function

function DeckIdentity(settings as object) as string
    return settings.baseUrl + "|" + settings.profiles[settings.selected].uuid
end function

function SlideIndices(raw as dynamic) as object
    ' Thumbnail indices are flat, zero-based across ALL groups, including disabled slides.
    if IsMap(raw)
        if IsMap(raw.presentation) then raw = raw.presentation
    end if
    if not IsMap(raw) then return {ok: false, error: "Unexpected presentation response."}
    if not IsList(raw.groups) then return {ok: false, error: "Presentation has no groups array."}
    indices = []
    ordinal = 0
    for each group in raw.groups
        if not IsMap(group) then return {ok: false, error: "Invalid slide group."}
        if not IsList(group.slides) then return {ok: false, error: "Invalid slide list."}
        for each slide in group.slides
            if not IsMap(slide) then return {ok: false, error: "Invalid slide."}
            if slide.enabled <> false then indices.Push(ordinal)
            ordinal++
        end for
    end for
    if indices.Count() = 0 then return {ok: false, error: "This presentation has no enabled slides."}
    if indices.Count() > 100 then return {ok: false, error: "Limit is 100 enabled slides. Split this presentation."}
    return {ok: true, indices: indices}
end function

function LibraryItems(raw as dynamic) as object
    if IsMap(raw) then raw = raw.items
    if not IsList(raw) then return {ok: false, error: "Unexpected library response."}
    rows = []
    for each item in raw
        if IsMap(item)
            if IsMap(item.id) then item = item.id
            if SafeText(item.uuid) <> "" and SafeText(item.name) <> ""
                rows.Push({uuid: item.uuid, name: item.name})
            end if
        end if
    end for
    return {ok: true, items: rows}
end function

function CacheRoot(mode as string) as string
    if mode = "screensaver" or mode = "settings" then return "cachefs:/pro-announcement-looper-ss/"
    return "cachefs:/pro-announcement-looper-player/"
end function

 ' Metadata-only check: safe on the SceneGraph render thread. Image loadStatus
' handles cache eviction in the UI; filesystem existence checks stay in ApiWorker.
function CacheMatches(raw as dynamic, identity as string) as boolean
    if not IsMap(raw) then return false
    if raw.identity <> identity then return false
    if not IsList(raw.files) then return false
    if raw.files.Count() < 1 or raw.files.Count() > 100 then return false
    if SafeText(raw.generation) = "" then return false
    for each path in raw.files
        if SafeText(path) = "" then return false
        if Left(path, Len(raw.generation)) <> raw.generation then return false
    end for
    return true
end function

' MAIN/TASK only. Never call this from a SceneGraph render callback.
function ValidCache(raw as dynamic, identity as string, fs = invalid as dynamic) as boolean
    if not CacheMatches(raw, identity) then return false
    if fs = invalid then fs = CreateObject("roFileSystem")
    if fs = invalid then return false
    for each path in raw.files
        if not fs.Exists(path) then return false
    end for
    return true
end function

function MenuPage(page as string, settings as object, paused as boolean) as object
    p = settings.profiles[settings.selected]
    pauseLabel = "Pause slideshow"
    if paused then pauseLabel = "Resume slideshow"
    schedule = "Off"
    if settings.scheduleEnabled then schedule = "On"
    remote = "Off"
    if settings.remoteEnabled then remote = "On"
    if page = "playback"
        return {title:"Playback", description:"Start, pause, or refresh the announcements on this TV.", actions:["start","pause","refresh","refreshAll"], labels:["Start slideshow",pauseLabel,"Refresh selected profile","Refresh all profiles"]}
    else if page = "profiles"
        return {title:"Profiles & timing", description:"Choose a presentation and how long each slide stays on screen.", actions:["chooseProfile","browse","duration","rename","add"], labels:["Select profile", "Choose presentation", "Seconds per slide: " + p.seconds.ToStr(), "Rename profile", "Add profile"]}
    else if page = "schedule"
        return {title:"Schedules & overrides", description:"Set automatic switches, or hold a profile until you resume the schedule.", actions:["scheduleEnabled","schedule","switchNow","resume"], labels:["Automatic schedule: " + schedule,"Edit selected profile's switch times","Show selected profile now","Resume automatic schedule"]}
    else if page = "connection"
        return {title:"Connection", description:"Connect to ProPresenter and manage optional remote control.", actions:["address","remote","help"], labels:["ProPresenter address","Remote actions: " + remote,"Unattended playback help"]}
    end if
    return {title:"Home", description:"Announcements for this TV. Choose a section to change its settings.", actions:["start","page:playback","page:profiles","page:schedule","page:connection"], labels:["Start slideshow","Playback & refresh","Profiles & timing","Schedules & overrides","Connection"]}
end function

' Compare ordered rendered content, not presentation names or volatile UI state.
function SameRenderedDeck(first as dynamic, second as dynamic) as boolean
    if not IsMap(first) or not IsMap(second) then return false
    if first.identity <> second.identity then return false
    if not IsList(first.hashes) or not IsList(second.hashes) then return false
    if first.hashes.Count() = 0 or first.hashes.Count() <> second.hashes.Count() then return false
    for i = 0 to first.hashes.Count() - 1
        if SafeText(first.hashes[i]) = "" then return false
        if first.hashes[i] <> second.hashes[i] then return false
    end for
    return true
end function

function RefreshOrder(settings as object, priority as integer) as object
    indices = []
    if settings.profiles[priority].uuid <> "" then indices.Push(priority)
    for i = 0 to settings.profiles.Count() - 1
        if i <> priority and settings.profiles[i].uuid <> "" then indices.Push(i)
    end for
    return indices
end function
