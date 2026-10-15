sub init()
    m.top.functionName = "RunRequest"
end sub

sub RunRequest()
    r = m.top.request
    m.port = CreateObject("roMessagePort")
    m.fs = CreateObject("roFileSystem")
    if r.action = "init"
        section = CreateObject("roRegistrySection", "ProAnnouncementLooperV1")
        rawSettings = invalid
        text = section.Read("settings")
        if text <> "" then rawSettings = ParseJson(text)
        settings = NormalizeSettings(rawSettings)
        m.fs.CreateDirectory(CacheRoot(r.mode))
        ' Remove obsolete 0.1 single-deck files after migrating settings.
        for each name in ListDir(CacheRoot(r.mode))
            if name = "current.json" or Right(name, 4) = ".jpg" then m.fs.Delete(CacheRoot(r.mode) + name)
        end for
        decks = []
        for i = 0 to settings.profiles.Count() - 1
            root = ProfileCacheRoot(r.mode, i)
            m.fs.CreateDirectory(root)
            cached = ReadCachedJson(root + "current.json")
            if not ValidCache(cached, DeckIdentity(ProfileSettings(settings, i))) then cached = invalid
            CleanupCache(root, cached)
            decks.Push(cached)
        end for
        m.top.result = {ok: true, action: r.action, settings: settings, decks: decks, cached: decks[settings.selected]}
    else if r.action = "save"
        section = CreateObject("roRegistrySection", "ProAnnouncementLooperV1")
        ok = section.Write("settings", FormatJson(r.settings))
        if ok then ok = section.Flush()
        m.top.result = {ok: ok, action: r.action, error: "Could not save settings."}
    else if r.action = "libraries" or r.action = "presentations"
        path = "/v1/libraries"
        if r.action = "presentations" then path = "/v1/library/" + UrlPart(r.library)
        response = GetJson(r.settings.baseUrl + path)
        if response.ok then response = LibraryItems(response.data)
        response.action = r.action
        m.top.result = response
    else if r.action = "fetch"
        m.top.result = FetchDeck(r)
    else if r.action = "commit"
        root = ProfileCacheRoot(r.mode, r.settings.selected)
        candidate = r.deck
        ok = ValidCache(candidate, DeckIdentity(r.settings))
        if ok then ok = WriteAsciiFile(root + "current.json", FormatJson(candidate))
        ' Do not remove the previous generation here; the scene may still be displaying it.
        m.top.result = {ok: ok, action: r.action, deck: candidate, error: "Could not store the cache index."}
    else if r.action = "discard"
        DeleteGeneration(r.deck)
        m.top.result = {ok: true, action: r.action}
    end if
end sub

function NewTransfer(url as string) as object
    transfer = CreateObject("roUrlTransfer")
    transfer.SetMessagePort(m.port)
    transfer.SetUrl(url)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.EnableEncodings(true)
    transfer.AddHeader("Accept", "application/json, image/jpeg")
    return transfer
end function

function TransferResult(transfer as object) as object
    timer = CreateObject("roTimespan")
    while timer.TotalMilliseconds() < 15000
        event = Wait(250, m.port)
        if type(event) = "roUrlEvent"
            if event.GetSourceIdentity() = transfer.GetIdentity()
                code = event.GetResponseCode()
                if code = 200 then return {ok: true, event: event}
                return {ok: false, error: "ProPresenter request failed (HTTP " + code.ToStr() + "). Check address, API access, and presentation."}
            end if
        end if
    end while
    transfer.AsyncCancel()
    return {ok: false, error: "Connection timed out. Existing cached slides are unchanged."}
end function

function GetJson(url as string) as object
    transfer = NewTransfer(url)
    if not transfer.AsyncGetToString() then return {ok: false, error: "Could not start the request."}
    response = TransferResult(transfer)
    if not response.ok then return response
    body = response.event.GetString()
    if Len(body) > 2097152 then return {ok: false, error: "API response is too large (limit 2 MB)."}
    data = ParseJson(body)
    if data = invalid then return {ok: false, error: "ProPresenter returned invalid JSON."}
    return {ok: true, data: data}
end function

function DownloadImage(url as string, path as string) as object
    transfer = NewTransfer(url)
    if not transfer.AsyncGetToFile(path) then return {ok: false, error: "Could not start image download."}
    response = TransferResult(transfer)
    if not response.ok then return response
    stat = m.fs.Stat(path)
    if stat = invalid then return {ok: false, error: "The image cache is unavailable."}
    if stat.size < 4 or stat.size > 4194304 then return {ok: false, error: "Slide image is empty or larger than 4 MB."}
    signature = CreateObject("roByteArray")
    if not signature.ReadFile(path, 0, 4) then return {ok: false, error: "Cached image was reclaimed."}
    if signature.Count() < 4 then return {ok: false, error: "Incomplete slide image."}
    isJpeg = signature[0] = 255 and signature[1] = 216
    isPng = signature[0] = 137 and signature[1] = 80 and signature[2] = 78 and signature[3] = 71
    if not isJpeg and not isPng then return {ok: false, error: "Unsupported slide image. Expected JPEG or PNG."}
    return {ok: true, bytes: stat.size}
end function

function FetchDeck(r as object) as object
    profile = r.settings.profiles[r.settings.selected]
    if profile.uuid = "" or r.settings.baseUrl = "" then return {ok: false, action: "fetch", error: "Set the computer address and choose a presentation first."}
    root = ProfileCacheRoot(r.mode, r.settings.selected)
    m.fs.CreateDirectory(root)
    ' At most the current deck plus one candidate is retained. Safe because only one
    ' worker is active per scene; player and screensaver have separate namespaces.
    CleanupCache(root, r.keep)
    retainedBytes = 0
    for slot = 0 to r.settings.profiles.Count() - 1
        cached = ReadCachedJson(ProfileCacheRoot(r.mode, slot) + "current.json")
        if IsMap(cached)
            if type(cached.bytes) = "roInt" or type(cached.bytes) = "Integer" then retainedBytes = retainedBytes + cached.bytes
        end if
    end for
    now = CreateObject("roDateTime")
    generation = root + now.AsSeconds().ToStr() + "-" + Rnd(1000000).ToStr() + "-"
    deck = {identity: DeckIdentity(r.settings), generation: generation, files: [], name: profile.name, cachedAt: now.ToISOString(), bytes: 0}
    response = GetJson(r.settings.baseUrl + "/v1/presentation/" + UrlPart(profile.uuid))
    if not response.ok
        response.action = "fetch"
        return response
    end if
    parsed = SlideIndices(response.data)
    if not parsed.ok
        parsed.action = "fetch"
        return parsed
    end if
    if IsMap(response.data.id) then deck.name = SafeText(response.data.id.name, deck.name)
    for each index in parsed.indices
        m.top.progress = "Downloading slide " + (deck.files.Count() + 1).ToStr() + " of " + parsed.indices.Count().ToStr()
        path = generation + index.ToStr() + ".jpg"
        url = r.settings.baseUrl + "/v1/presentation/" + UrlPart(profile.uuid) + "/thumbnail/" + index.ToStr() + "?quality=1920&thumbnail_type=jpeg"
        image = DownloadImage(url, path)
        if not image.ok
            m.fs.Delete(path)
            DeleteGeneration(deck)
            return {ok: false, action: "fetch", error: image.error}
        end if
        deck.files.Push(path)
        deck.bytes = deck.bytes + image.bytes
        if deck.bytes + retainedBytes > 67108864
            DeleteGeneration(deck)
            return {ok: false, action: "fetch", error: "All profile caches plus refresh exceed 64 MB. Use smaller presentations."}
        end if
        if deck.bytes > 33554432
            DeleteGeneration(deck)
            return {ok: false, action: "fetch", error: "Slide collection exceeds the 32 MB cache limit. Use fewer slides."}
        end if
    end for
    ' Recheck every file: cachefs may be evicted even during a download.
    if not ValidCache(deck, deck.identity)
        DeleteGeneration(deck)
        return {ok: false, action: "fetch", error: "Roku reclaimed the image cache. Try a smaller presentation."}
    end if
    return {ok: true, action: "fetch", deck: deck}
end function

sub DeleteGeneration(deck as dynamic)
    if not IsMap(deck) then return
    if not IsList(deck.files) then return
    for each path in deck.files
        m.fs.Delete(path)
    end for
end sub

sub CleanupCache(root as string, keep as dynamic)
    prefix = ""
    if IsMap(keep) then prefix = SafeText(keep.generation)
    for each name in ListDir(root)
        path = root + name
        if name <> "current.json"
            preserve = false
            if prefix <> "" then preserve = Left(path, Len(prefix)) = prefix
            if not preserve then m.fs.Delete(path)
        end if
    end for
end sub

' TASK-only: missing cache files are normal, not JSON parse errors.
function ReadCachedJson(path as string) as dynamic
    if not m.fs.Exists(path) then return invalid
    text = ReadAsciiFile(path)
    if text = "" then return invalid
    return ParseJson(text)
end function
