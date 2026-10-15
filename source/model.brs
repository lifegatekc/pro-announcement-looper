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

function DefaultSettings() as object
    return {baseUrl: "", selected: 0, profiles: [
        {label: "Main Service", uuid: "", name: "", seconds: 13}
        {label: "Youth Service", uuid: "", name: "", seconds: 13}
    ]}
end function

function NormalizeSettings(raw as dynamic) as object
    result = DefaultSettings()
    if not IsMap(raw) then return result
    result.baseUrl = SafeText(raw.baseUrl)
    if raw.selected = 1 then result.selected = 1
    if not IsList(raw.profiles) then return result
    for i = 0 to 1
        if i < raw.profiles.Count()
            p = raw.profiles[i]
            if IsMap(p)
                result.profiles[i].uuid = SafeText(p.uuid)
                result.profiles[i].name = SafeText(p.name)
                seconds = Val(SafeText(p.seconds, "13"))
                if type(p.seconds) = "Integer" or type(p.seconds) = "roInt" then seconds = p.seconds
                if seconds >= 1 and seconds <= 3600 then result.profiles[i].seconds = Int(seconds)
            end if
        end if
    end for
    return result
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
    if mode = "screensaver" or mode = "settings" then return "cachefs:/announcement-loop-ss/"
    return "cachefs:/announcement-loop-player/"
end function

function ValidCache(raw as dynamic, identity as string, fs = invalid as dynamic) as boolean
    if not IsMap(raw) then return false
    if raw.identity <> identity then return false
    if not IsList(raw.files) then return false
    if raw.files.Count() < 1 or raw.files.Count() > 100 then return false
    if SafeText(raw.generation) = "" then return false
    if fs = invalid then fs = CreateObject("roFileSystem")
    for each path in raw.files
        if SafeText(path) = "" then return false
        if Left(path, Len(raw.generation)) <> raw.generation then return false
        if not fs.Exists(path) then return false
    end for
    return true
end function
