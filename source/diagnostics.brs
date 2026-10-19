' Called before scene/worker startup so an early launch failure does not hide the prior exit.
' The registry is local, bounded and separate from presentation settings.
function CaptureLastExitDiagnostics(mode as string) as object
    previous = invalid
    report = BuildExitDiagnostics(invalid, invalid, mode, "", "")
    try
        app = CreateObject("roAppInfo")
        clock = CreateObject("roDateTime")
        section = CreateObject("roRegistrySection", "PALExitDiagnosticsV1")
        key = mode + "-" + app.GetID()
        if section.Exists(key) then previous = ParseJson(section.Read(key))
        report = BuildExitDiagnostics(previous, invalid, mode, app.GetVersion(), clock.ToISOString())
        manager = CreateObject("roAppManager")
        if manager <> invalid
            report = BuildExitDiagnostics(previous, manager.GetLastExitInfo(), mode, app.GetVersion(), clock.ToISOString())
        end if
        encoded = FormatJson(report)
        ' All fields are whitelisted and capped; never print or persist console_log.
        if Len(encoded) <= 4096
            if section.Write(key, encoded)
                if not section.Flush() then report.storage_status = "flush_failed"
            else
                report.storage_status = "write_failed"
            end if
        else
            report.storage_status = "size_limit"
        end if
    catch error
        ' Diagnostic failures must never prevent slideshow startup.
        report.capture_status = "capture_failed"
    end try
    return report
end function
