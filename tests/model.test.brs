sub Main()
    m.passed = 0
    m.failed = 0
    defaults = NormalizeSettings(invalid)
    Check(defaults.profiles.Count() = 2, "two default profiles")
    Check(defaults.profiles[0].seconds = 13, "13-second default")
    Check(defaults.profiles[1].label = "Youth Service", "youth profile")
    restored = NormalizeSettings({selected: 1, baseUrl: "http://church:50001", profiles: [
        {uuid: "main", name: "Main", seconds: 22}, {uuid: "youth", name: "Youth", seconds: 17}]})
    Check(restored.selected = 1, "selected profile restores")
    Check(restored.profiles[0].seconds = 22, "numeric duration restores")
    Check(restored.profiles[1].uuid = "youth", "presentation ID restores")
    Check(DeckIdentity(restored) = "http://church:50001|youth", "cache tied to host and presentation")
    malformed = NormalizeSettings({profiles: [invalid, {seconds: 99999}], selected: 10})
    Check(malformed.selected = 0, "invalid selected profile falls back")
    Check(malformed.profiles[1].seconds = 13, "invalid duration falls back")
    parsed = SlideIndices({groups:[{slides:[{enabled:true},{enabled:false}]},{slides:[{enabled:true},{enabled:true}]}]})
    Check(parsed.ok, "valid grouped deck accepted")
    Check(FormatJson(parsed.indices) = "[0,2,3]", "disabled slides retain API ordinal across groups")
    Check(not SlideIndices({groups:[]}).ok, "empty deck rejected")
    Check(not SlideIndices({groups:[{slides:[{enabled:false}]}]}).ok, "all-disabled deck rejected")
    Check(not SlideIndices({groups:[{}]}).ok, "malformed groups rejected")
    Check(not SlideIndices(invalid).ok, "invalid response rejected")
    Check(SlideIndices({presentation:{groups:[{slides:[{}]}]}}).ok, "wrapped presentation supported")
    slides = []
    for i = 0 to 100
        slides.Push({enabled:true})
    end for
    Check(not SlideIndices({groups:[{slides:slides}]}).ok, "oversized deck rejected")
    libraries = LibraryItems([{id:{uuid:"lib",name:"Church",index:0}}])
    Check(libraries.items[0].name = "Church", "library identifier wrapper parsed")
    items = LibraryItems({items:[{uuid:"main",name:"Main Announcements"},{name:"broken"}]})
    Check(items.items.Count() = 1, "presentation list filters invalid identifiers")
    Check(not LibraryItems(invalid).ok, "invalid library response rejected")
    Check(CacheRoot("settings") = CacheRoot("screensaver"), "screensaver settings use screensaver cache")
    Check(CacheRoot("player") <> CacheRoot("screensaver"), "separate caches prevent cross-process deletion")
    Check(not ValidCache(invalid, "x"), "missing cache rejected")
    Check(not ValidCache({identity:"other"}, "x"), "wrong cache identity rejected")
    Check(not ValidCache({identity:"x",files:[],generation:"x"}, "x"), "empty cache rejected")
    Check(not ValidCache({identity:"x",files:["other/slide.jpg"],generation:"cachefs:/safe/"}, "x"), "cache path outside generation rejected")
    missingFs = {Exists: function(path)
        return false
    end function}
    Check(not ValidCache({identity:"x",files:["cachefs:/missing/0.jpg"],generation:"cachefs:/missing/"}, "x", missingFs), "evicted cached files rejected")
    Check(NormalizeBaseUrl(" 192.168.1.50 ") = "http://192.168.1.50:50001", "default API port")
    Check(NormalizeBaseUrl("http://church.local:1234/") = "http://church.local:1234", "trailing slash removed")
    Check(NormalizeBaseUrl("https://church.local:50001") = "https://church.local:50001", "HTTPS preserved")
    Check(NormalizeBaseUrl("http://church:65536") = "", "out-of-range port rejected")
    Check(NormalizeBaseUrl("http://church:0") = "", "zero port rejected")
    Check(NormalizeBaseUrl("http://user:pass@church") = "", "credentials in URL rejected")
    Check(NormalizeBaseUrl("http://church/v1/trigger") = "", "URL paths rejected")
    Check(NormalizeBaseUrl("") = "", "empty address rejected")
    a = {identity:"host|deck",hashes:["hash-a","hash-b"]}
    b = {identity:"host|deck",hashes:["hash-a","hash-b"]}
    Check(SameRenderedDeck(a,b), "identical ordered slide images keep existing cache")
    b.hashes = ["hash-a","changed-artwork"]
    Check(not SameRenderedDeck(a,b), "image-only edits invalidate cache")
    b.hashes = ["hash-b","hash-a"]
    Check(not SameRenderedDeck(a,b), "slide reordering invalidates cache")
    b.hashes = ["hash-a"]
    Check(not SameRenderedDeck(a,b), "slide removal invalidates cache")
    b = {identity:"another-host|deck",hashes:["hash-a","hash-b"]}
    Check(not SameRenderedDeck(a,b), "different source cannot reuse cache")
    Check(not SameRenderedDeck(a,{identity:"host|deck"}), "legacy cache requires image comparison")
    Check(not SameRenderedDeck({identity:"x",hashes:[""]},{identity:"x",hashes:[""]}), "missing fingerprint never counts as unchanged")
    s = DefaultSettings()
    s.profiles[0].uuid = "main"
    s.profiles[1].uuid = "closed"
    s.profiles.Push(NewProfile("Unconfigured"))
    Check(FormatJson(RefreshOrder(s,1)) = "[1,0]", "startup checks current scheduled profile before others")
    s.profiles[0].uuid = ""
    Check(FormatJson(RefreshOrder(s,0)) = "[1]", "startup skips unconfigured profiles")
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
