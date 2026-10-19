' Keep only bounded termination metadata. Never retain Roku's raw console_log.
function ExitDiagnosticRecord(info as dynamic) as dynamic
    if not IsMap(info) then return invalid
    code = Left(SafeText(info.exit_code), 96)
    if code = "" then return invalid
    record = {exit_code:code, timestamp:Left(SafeText(info.timestamp),64)}
    for each field in ["app_state", "media_player_state"]
        value = Left(SafeText(info[field]),32)
        if value <> "" then record[field] = value
    end for
    limit = info.mem_limit
    if type(limit) = "Integer" or type(limit) = "roInt" or type(limit) = "Float" or type(limit) = "roFloat"
        if limit >= 0 and limit <= 1048576 then record.mem_limit = Int(limit)
    end if
    return record
end function

function BuildExitDiagnostics(previous as dynamic, info as dynamic, mode as string, version as string, checkedAt as string) as object
    history = []
    if IsMap(previous)
        if IsList(previous.exits)
            for each old in previous.exits
                safe = ExitDiagnosticRecord(old)
                if safe <> invalid then history.Push(safe)
            end for
        end if
    end if
    status = "no_record"
    current = ExitDiagnosticRecord(info)
    if current <> invalid
        status = "available"
        duplicate = false
        for each old in history
            if old.timestamp = current.timestamp and old.exit_code = current.exit_code then duplicate = true
        end for
        if not duplicate then history.Push(current)
    end if
    while history.Count() > 8
        history.Shift()
    end while
    return {schema:1, mode:mode, captured_by_version:version, checked_at:checkedAt, capture_status:status, exits:history}
end function
