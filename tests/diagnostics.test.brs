sub Main()
    m.passed = 0
    m.failed = 0
    Check(ExitDiagnosticRecord(invalid) = invalid, "no exit report is safe")
    Check(ExitDiagnosticRecord({console_log:"private"}) = invalid, "missing exit code rejected")
    raw = {exit_code:"EXIT_CHANNEL_MEM_LIMIT_FG", timestamp:"2026-01-01T00:00:00Z", app_state:"foreground", mem_limit:256, media_player_state:"stopped", console_log:"private slide and address", other:"private"}
    record = ExitDiagnosticRecord(raw)
    Check(record.exit_code = raw.exit_code and record.mem_limit = 256, "exit cause and memory limit retained")
    Check(not record.DoesExist("console_log") and not record.DoesExist("other"), "console and unexpected personal data excluded")
    Check(ExitDiagnosticRecord({exit_code:"EXIT_UNKNOWN"}).exit_code = "EXIT_UNKNOWN", "unknown exit is retained without implying a crash")
    report = BuildExitDiagnostics(invalid,raw,"player","0.9.1","now")
    Check(report.exits.Count() = 1 and report.capture_status = "available", "first exit captured")
    Check(report.captured_by_version = "0.9.1" and report.mode = "player", "capture version and entry point identified")
    again = BuildExitDiagnostics(report,raw,"player","0.9.1","later")
    Check(again.exits.Count() = 1, "same Roku exit is not duplicated across launches")
    absent = BuildExitDiagnostics(again,invalid,"player","0.9.1","later")
    Check(absent.exits.Count() = 1 and absent.capture_status = "no_record", "missing new report preserves earlier evidence")
    malformed = BuildExitDiagnostics({exits:[invalid,{},raw]},invalid,"screensaver","0.9.1","now")
    Check(malformed.exits.Count() = 1 and not malformed.exits[0].DoesExist("console_log"), "saved records are validated and sanitized")
    Check(BuildExitDiagnostics({exits:"broken"},invalid,"player","0.9.1","now").exits.Count() = 0, "malformed saved history is ignored")
    bounded = report
    for i = 1 to 20
        bounded = BuildExitDiagnostics(bounded,{exit_code:"EXIT_SYSTEM_KILL",timestamp:i.ToStr()},"player","0.9.1","now")
    end for
    Check(bounded.exits.Count() = 8 and bounded.exits[0].timestamp = "13" and bounded.exits[7].timestamp = "20", "only the latest eight exit events survive")
    changed = BuildExitDiagnostics(report,{exit_code:"EXIT_OUT_OF_MEMORY",timestamp:raw.timestamp},"player","0.9.1","now")
    Check(changed.exits.Count() = 2, "different cause at same timestamp is not lost")
    Check(not ExitDiagnosticRecord({exit_code:"EXIT_UNKNOWN",mem_limit:"bad"}).DoesExist("mem_limit"), "invalid memory value is omitted")
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
