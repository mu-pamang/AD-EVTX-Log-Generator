# Windows Event Log Generator - WIN10-CLIENT v8
# Uses Task Scheduler with SYSTEM account to bypass SeSystemtimePrivilege

$REAL_TIME   = Get-Date
$DAYS_BEFORE = 8
$ATTACK_DATE = [datetime]"2026-05-22"
$START_DATE  = $ATTACK_DATE.AddDays(-$DAYS_BEFORE)

# Scan actual files
$userProfile = $env:USERPROFILE
$scanPaths = @("$userProfile\Documents","$userProfile\Desktop","$userProfile\Downloads")
$discoveredFiles = @()
foreach ($p in $scanPaths) {
    if (Test-Path $p) {
        $discoveredFiles += Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike "*Generate-user-EventLogs*" }
    }
}
if ($discoveredFiles.Count -lt 5) {
    $basePath = "$userProfile\Documents"
    @("Q1_report.xlsx","budget_2024.xlsx","meeting_notes.docx","project_plan.docx","HR_list.xlsx","client_contact.xlsx") | ForEach-Object {
        Set-Content "$basePath\$_" -Value ("dummy content " * 100) -Force
    }
    $discoveredFiles = Get-ChildItem $basePath -Recurse -File
}

# Build file list string for inner script
$fileListStr = ($discoveredFiles.FullName | ForEach-Object { "`"$_`"" }) -join ","

# Write inner worker script (runs as SYSTEM via Task Scheduler)
$workerPath = "$env:TEMP\log_worker.ps1"
@"
param([string]`$DateStr)
`$targetDate = [datetime]`$DateStr

# Set system time
Set-Date -Date `$targetDate.Date.AddHours(9) | Out-Null

`$files = @($fileListStr)

function Invoke-NormalFileAccess {
    `$f = `$files | Get-Random
    if (Test-Path `$f) { Get-Content `$f -ErrorAction SilentlyContinue | Out-Null }
}
function Invoke-NormalNetworkAccess {
    foreach (`$share in @("\\DC01\SYSVOL","\\DC01\NETLOGON")) {
        try { Get-ChildItem `$share -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}
function Invoke-NormalLogon {
    net use \\DC01\IPC$ /user:CORP\jdoe "qwer1234!" 2>`$null
    net use \\DC01\IPC$ /delete 2>`$null
}
function Invoke-FalsePositive_AVScan {
    `$paths = @("`$env:USERPROFILE\Documents","`$env:USERPROFILE\Desktop")
    foreach (`$p in `$paths) {
        if (Test-Path `$p) {
            Get-ChildItem `$p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                try { [System.IO.File]::ReadAllBytes(`$_.FullName) | Out-Null } catch {}
                Start-Sleep -Milliseconds 30
            }
        }
    }
}
function Invoke-FalsePositive_AuthFail {
    for (`$i = 1; `$i -le 20; `$i++) {
        net use \\DC01\IPC$ /user:CORP\jdoe "wrongpassword`$i" 2>`$null
        Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 800)
    }
    net use \\DC01\IPC$ /delete 2>`$null
}

`$count  = 0
`$target = Get-Random -Minimum 300 -Maximum 400
while (`$count -lt `$target) {
    `$current_time = (Get-Date).AddSeconds((Get-Random -Minimum 30 -Maximum 180))
    Set-Date -Date `$current_time | Out-Null
    if ((Get-Date).Hour -ge 18) { break }
    `$action = Get-Random -Minimum 1 -Maximum 4
    switch (`$action) {
        1 { Invoke-NormalFileAccess }
        2 { Invoke-NormalNetworkAccess }
        3 { Invoke-NormalLogon }
        4 { Invoke-NormalFileAccess; Invoke-NormalFileAccess }
    }
    `$count++
    Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 100)
}

if (`$targetDate.Day % 2 -eq 0) {
    Set-Date -Date `$targetDate.Date.AddHours(2).AddMinutes(30) | Out-Null
    Invoke-FalsePositive_AVScan
}
if (`$targetDate.Day % 3 -eq 0) {
    Set-Date -Date `$targetDate.Date.AddHours(8).AddMinutes(50) | Out-Null
    Invoke-FalsePositive_AuthFail
}
"@ | Set-Content $workerPath -Encoding UTF8

Write-Host "======================================"
Write-Host " Event Log Generator - WIN10-CLIENT v8"
Write-Host " Period: $($START_DATE.ToString('MM/dd')) ~ $($ATTACK_DATE.AddDays(-1).ToString('MM/dd'))"
Write-Host "======================================"

# [1] Clear logs
Write-Host "`n[1] Clearing event logs..."
wevtutil cl Security    2>$null
wevtutil cl System      2>$null
wevtutil cl Application 2>$null
Write-Host "  Done"

# [2] Run worker via Task Scheduler as SYSTEM for each day
Write-Host "`n[2] Generating logs by date via SYSTEM task..."

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $current_date = $START_DATE.AddDays($day)
    $dow = $current_date.DayOfWeek
    if ($dow -eq "Saturday" -or $dow -eq "Sunday") {
        Write-Host "`n  [SKIP] $($current_date.ToString('yyyy-MM-dd')) weekend"
        continue
    }

    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] $($current_date.ToString('yyyy-MM-dd')) generating..."

    $taskName = "LogGen_$day"
    $dateArg  = $current_date.ToString('yyyy-MM-dd')

    # Register task to run as SYSTEM
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
                   -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$workerPath`" -DateStr $dateArg"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -RunLevel Highest -User "SYSTEM" -Settings $settings -Force | Out-Null

    # Run immediately
    Start-ScheduledTask -TaskName $taskName

    # Wait for completion
    do {
        Start-Sleep -Seconds 5
        $state = (Get-ScheduledTask -TaskName $taskName).State
    } while ($state -eq "Running")

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
    Write-Host "  Done"
}

# [3] Restore system time
Write-Host "`n[3] Restoring system time..."
$restoreTask = "LogGen_Restore"
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
               -Argument "-NonInteractive -Command Set-Date -Date '$($REAL_TIME.ToString('yyyy-MM-dd HH:mm:ss'))'"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
Register-ScheduledTask -TaskName $restoreTask -Action $action -Trigger $trigger `
    -RunLevel Highest -User "SYSTEM" -Force | Out-Null
Start-ScheduledTask -TaskName $restoreTask
Start-Sleep -Seconds 5
Unregister-ScheduledTask -TaskName $restoreTask -Confirm:$false | Out-Null
Write-Host "  Restored: $($REAL_TIME.ToString('yyyy-MM-dd HH:mm:ss'))"

# [4] Cleanup
Write-Host "`n[4] Cleaning up traces..."
Remove-Item $workerPath -Force -ErrorAction SilentlyContinue

$dl = "$env:USERPROFILE\Downloads"
@("$dl\Generate-user-EventLogs.ps1","$dl\Generate-EventLogs-v4.ps1") | ForEach-Object {
    Remove-Item $_ -Force -ErrorAction SilentlyContinue
}

Clear-History
Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue

@(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History-journal",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data"
) | ForEach-Object { Remove-Item $_ -Force -Recurse -ErrorAction SilentlyContinue }

Remove-Item "C:\Windows\Prefetch\POWERSHELL*" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Prefetch\GENERATE*"   -Force -ErrorAction SilentlyContinue

Start-Process "cmd.exe" -ArgumentList "/c ping 127.0.0.1 -n 3 > nul & del /f /q `"$($MyInvocation.MyCommand.Path)`"" -WindowStyle Hidden
Write-Host "  All traces cleaned"

Write-Host "`n======================================"
Write-Host " All done! Ready for attack simulation"
Write-Host "======================================"
