# Registers a Windows scheduled task that runs tools/sync.py every night.
#
#   pwsh tools/schedule-sync.ps1                 # 3:00 AM
#   pwsh tools/schedule-sync.ps1 -At 23:30
#   pwsh tools/schedule-sync.ps1 -Remove
#
# The task runs as you, only while you're logged in to Windows, so git, gh and
# claude use your normal logins. If the PC is off at that time it runs at the next
# chance. Output goes to %LOCALAPPDATA%\RageBuster\sync.log.

param(
    [string]$At = "03:00",
    [string]$WowDir = "",   # empty: sync.py reads wowDir from local-settings.json each run
    [switch]$Remove
)

$ErrorActionPreference = "Stop"
$TaskName = "RageBuster nightly sync"

if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed '$TaskName'."
    return
}

$uv = (Get-Command uv -ErrorAction Stop).Source
$script = Join-Path $PSScriptRoot "sync.py"
$logDir = Join-Path $env:LOCALAPPDATA "RageBuster"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "sync.log"

# cmd.exe handles the redirect, so the log keeps every run
$wowArg = if ($WowDir) { " --wow-dir `"$WowDir`"" } else { "" }
$command = "`"$uv`" run `"$script`"$wowArg >> `"$log`" 2>&1"
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $command" -WorkingDirectory (Split-Path $PSScriptRoot)
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Scheduled '$TaskName' daily at $At. Log: $log"
Write-Host "Run it now with: Start-ScheduledTask -TaskName '$TaskName'"
