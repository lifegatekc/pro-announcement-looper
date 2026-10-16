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
    return {label: label, uuid: "", name: "", seconds: 13, refreshMinutes: 0, schedule: ""}
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
    if type(raw.overrideUntil) = "Integer" or type(raw.overrideUntil) = "roInt" or type(raw.overrideUntil) = "Double" or type(raw.overrideUntil) = "Float" then result.overrideUntil = raw.overrideUntil
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
            interval = p.refreshMinutes
            if type(interval) = "Integer" or type(interval) = "roInt"
                if interval >= 0 and interval <= 1440 then target.refreshMinutes = interval
            end if
        end if
    end for
    if type(raw.selected) = "Integer" or type(raw.selected) = "roInt"
        if raw.selected >= 0 and raw.selected < result.profiles.Count() then result.selected = raw.selected
    end if
    if type(raw.overrideProfile) = "Integer" or type(raw.overrideProfile) = "roInt"
        if raw.overrideProfile >= 0 and raw.overrideProfile < result.profiles.Count() then result.overrideProfile = raw.overrideProfile
    end if
    if result.profiles[result.selected].uuid = ""
        for i = 0 to result.profiles.Count() - 1
            if result.profiles[i].uuid <> ""
                result.selected = i
                exit for
            end if
        end for
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

function ScheduledProfile(settings as object, day as integer, minute as integer, utcSeconds = 0 as double) as integer
    if settings.manualOverride
        untilTime = 0
        if settings.DoesExist("overrideUntil") then untilTime = settings.overrideUntil
        if untilTime = 0 or utcSeconds < untilTime then return settings.overrideProfile
    end if
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
    if action = "refreshAll" then return {ok:true,action:"refreshAll"}
    if action = "refresh" and not info.DoesExist("profile") then return {ok:true,action:"refreshAll"}
    if action = "switch" or action = "refresh"
        number = SafeText(info.profile)
        pattern = CreateObject("roRegex", "^[1-8]$", "")
        if pattern.IsMatch(number)
            index = Val(number) - 1
            if index < settings.profiles.Count()
                if action = "refresh" and settings.profiles[index].uuid = "" then return {ok:false}
                return {ok: true, action: action, index: Int(index)}
            end if
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
    schedule = "Off"
    if settings.scheduleEnabled then schedule = "On"
    remote = "Off"
    if settings.remoteEnabled then remote = "On"
    if page = "detail"
        return {title:p.label, description:"Edit this presentation here. Only Show now changes what the TV displays.", actions:["showNow","browse","duration","refresh","interval","rename","remove"], labels:["Show now","Choose ProPresenter presentation","Seconds per slide: " + p.seconds.ToStr(),"Refresh slides","Auto refresh: " + RefreshIntervalLabel(p.refreshMinutes),"Rename","Remove from this TV"]}
    else if page = "schedule"
        return {title:"Schedule", description:"Plan what this TV shows throughout the week. Times use the Roku local clock.", actions:["scheduleEnabled","schedule","resume"], labels:["Automatic schedule: " + schedule,"View / edit switch times","Resume schedule"]}
    else if page = "connection"
        return {title:"Connection & TV settings", description:"Connect to ProPresenter and manage optional remote control.", actions:["address","remote","demo","help"], labels:["ProPresenter address","Remote actions: " + remote,"Try offline demo","Unattended playback help"]}
    end if
    return {title:"Home", description:"Choose what this TV shows and when it changes.", actions:["start","page:configured","page:schedule","page:connection"], labels:["Start slideshow","Presentations","Schedule","Connection & TV settings"]}
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

' Preserve existing schedule strings while presenting individual editable entries.
function ScheduleEntries(text as string) as object
    entries = []
    if text.Trim() = "" then return entries
    for each part in text.Split(",")
        words = part.Trim().Split(" ")
        entries.Push({day: words[0], hour: Int(Val(Left(words[1],2))), minute: Int(Val(Right(words[1],2)))})
    end for
    return entries
end function

function ScheduleEntryText(entry as object) as string
    return entry.day + " " + TwoDigits(entry.hour) + ":" + TwoDigits(entry.minute)
end function

function ScheduleEntryLabel(entry as object) as string
    hour = entry.hour mod 12
    if hour = 0 then hour = 12
    period = " AM"
    if entry.hour >= 12 then period = " PM"
    day = entry.day
    if LCase(day) = "daily" then day = "Every day"
    return day + " at " + hour.ToStr() + ":" + TwoDigits(entry.minute) + period
end function

function JoinSchedule(entries as object) as string
    text = ""
    for each entry in entries
        if text <> "" then text = text + ", "
        text = text + ScheduleEntryText(entry)
    end for
    return text
end function

function TwoDigits(value as integer) as string
    text = value.ToStr().Trim()
    if value < 10 then text = "0" + text
    return text
end function

' Slots stay stable so existing cache paths and remote presentation numbers survive removal.
function AvailableSlot(settings as object) as integer
    for i = 0 to settings.profiles.Count() - 1
        if settings.profiles[i].uuid = "" then return i
    end for
    if settings.profiles.Count() < 8 then return settings.profiles.Count()
    return -1
end function

function ScheduleTimeline(settings as object) as object
    rows = []
    for i = 0 to settings.profiles.Count() - 1
        if settings.profiles[i].uuid <> ""
            entries = ScheduleEntries(settings.profiles[i].schedule)
            for j = 0 to entries.Count() - 1
                e = entries[j]
                minute = ParseSchedule(ScheduleEntryText(e)).events[0]
                row = {profile:i, entry:j, rule:e, sortMinute:minute}
                position = 0
                while position < rows.Count()
                    if rows[position].sortMinute > minute then exit while
                    position++
                end while
                rows.Push(row)
                cursor = rows.Count() - 1
                while cursor > position
                    rows[cursor] = rows[cursor - 1]
                    cursor--
                end while
                rows[position] = row
            end for
        end if
    end for
    return rows
end function

function NextSwitchDelay(settings as object, day as integer, minute as integer) as integer
    soonest = 10081
    for each p in settings.profiles
        if p.uuid <> ""
            for each eventMinute in ParseSchedule(p.schedule).events
                distance = (eventMinute - day * 1440 - minute + 10080) mod 10080
                if distance = 0 then distance = 10080
                if distance < soonest then soonest = distance
            end for
        end if
    end for
    if soonest = 10081 then return 0
    return soonest
end function

function ApplyScheduleEdit(settings as object, source as integer, entryIndex as integer, draft as object, remove as boolean) as boolean
    target = draft.profile
    if not remove
        if target < 0 or target >= settings.profiles.Count() then return false
        if settings.profiles[target].uuid = "" then return false
        entries = ScheduleEntries(settings.profiles[target].schedule)
        if (source <> target or entryIndex < 0) and entries.Count() >= 16 then return false
    end if
    if source >= 0 and entryIndex >= 0
        old = ScheduleEntries(settings.profiles[source].schedule)
        old.Delete(entryIndex)
        settings.profiles[source].schedule = JoinSchedule(old)
    end if
    if not remove
        entries = ScheduleEntries(settings.profiles[target].schedule)
        entries.Push({day:draft.day,hour:draft.hour,minute:draft.minute})
        settings.profiles[target].schedule = JoinSchedule(entries)
    end if
    return true
end function

function RefreshIntervalLabel(minutes as integer) as string
    if minutes = 0 then return "On open only"
    if minutes = 1 then return "Every minute"
    return "Every " + minutes.ToStr() + " minutes"
end function

' Elapsed milliseconds are monotonic; a wall-clock/timezone change cannot cause a retry storm.
function DueRefresh(settings as object, elapsed as double, attempts as object, priority as integer) as integer
    for each index in RefreshOrder(settings,priority)
        minutes = settings.profiles[index].refreshMinutes
        if minutes > 0
            last = 0
            key = index.ToStr()
            if attempts.DoesExist(key) then last = attempts[key]
            if elapsed - last >= minutes * 60000 then return index
        end if
    end for
    return -1
end function

function DemoSettings() as object
    settings = DefaultSettings()
    settings.profiles[0] = NewProfile("Offline demo")
    settings.profiles[0].uuid = "bundled-demo"
    settings.profiles[0].name = "Sample announcements"
    settings.profiles[0].seconds = 6
    return settings
end function

function DemoDeck() as object
    return {identity:"|bundled-demo",generation:"pkg:/images/demo/",files:["pkg:/images/demo/0.png","pkg:/images/demo/1.png","pkg:/images/demo/2.png"]}
end function
