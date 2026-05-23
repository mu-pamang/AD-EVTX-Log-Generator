# Windows Event Log Generator - WIN10-CLIENT v6
# Run as Administrator

$DAYS_BEFORE = 8
$ATTACK_DATE = [datetime]"2026-05-22"
$START_DATE  = $ATTACK_DATE.AddDays(-$DAYS_BEFORE)
$REAL_TIME   = Get-Date

# Audit policy via secedit
$seceditCfg = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Event Audit]
AuditSystemEvents=0
AuditLogonEvents=3
AuditObjectAccess=3
AuditPrivilegeUse=0
AuditPolicyChange=0
AuditAccountManage=0
AuditProcessTracking=1
AuditDSAccess=0
AuditAccountLogon=3
"@
$cfgPath = "$env:TEMP\audit.cfg"
$seceditCfg | Set-Content $cfgPath -Encoding Unicode
secedit /configure /db "$env:TEMP\audit.sdb" /cfg $cfgPath /quiet 2>$null
Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\audit.sdb" -Force -ErrorAction SilentlyContinue

# Scan actual files (exclude this script)
$userProfile = $env:USERPROFILE
$scanPaths = @("$userProfile\Documents", "$userProfile\Desktop", "$userProfile\Downloads")
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
Write-Host "[+] Found $($discoveredFiles.Count) files"

# Normal actions
function Invoke-NormalFileAccess {
    $file = ($discoveredFiles | Get-Random).FullName
    Get-Content $file -ErrorAction SilentlyContinue | Out-Null
}
function Invoke-NormalNetworkAccess {
    foreach ($share in @("\\DC01\SYSVOL","\\DC01\NETLOGON")) {
        try { Get-ChildItem $share -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}
function Invoke-NormalLogon {
    # net use triggers 4648 + 5140
    net use \\DC01\IPC$ /user:CORP\jdoe "qwer1234!" 2>$null
    net use \\DC01\IPC$ /delete 2>$null
}

# False positive actions
function Invoke-FalsePositive_AVScan {
    Write-Host "  [FP] AV scan pattern..."
    foreach ($p in @("$userProfile\Documents","$userProfile\Desktop")) {
        if (Test-Path $p) {
            Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                try { [System.IO.File]::ReadAllBytes($_.FullName) | Out-Null } catch {}
                Start-Sleep -Milliseconds 30
            }
        }
    }
}
function Invoke-FalsePositive_AuthFail {
    Write-Host "  [FP] Auth failure pattern..."
    for ($i = 1; $i -le 20; $i++) {
        net use \\DC01\IPC$ /user:CORP\jdoe "wrongpassword$i" 2>$null
        Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 2000)
    }
    net use \\DC01\IPC$ /delete 2>$null
}

Write-Host "======================================"
Write-Host " Event Log Generator - WIN10-CLIENT"
Write-Host " Period: $($START_DATE.ToString('MM/dd')) ~ $($ATTACK_DATE.AddDays(-1).ToString('MM/dd'))"
Write-Host "======================================"

# [1] Clear existing logs
Write-Host "`n[1] Clearing event logs..."
wevtutil cl Security 2>$null
wevtutil cl System   2>$null
wevtutil cl Application 2>$null
Write-Host "  Done"

# [2] Generate logs by date
Write-Host "`n[2] Generating logs by date..."

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $current_date = $START_DATE.AddDays($day)
    $dow = $current_date.DayOfWeek
    if ($dow -eq "Saturday" -or $dow -eq "Sunday") {
        Write-Host "`n  [SKIP] $($current_date.ToString('yyyy-MM-dd')) weekend"
        continue
    }

    # Set system time to 09:00 of that day
    $work_start = $current_date.Date.AddHours(9)
    Set-Date -Date $work_start | Out-Null
    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] $($current_date.ToString('yyyy-MM-dd')) generating..."

    $count  = 0
    $target = Get-Random -Minimum 300 -Maximum 400

    while ($count -lt $target) {
        # Advance time naturally
        $current_time = (Get-Date).AddSeconds((Get-Random -Minimum 30 -Maximum 180))
        Set-Date -Date $current_time | Out-Null

        # Stop at 18:00
        if ((Get-Date).Hour -ge 18) { break }

        $action = Get-Random -Minimum 1 -Maximum 4
        switch ($action) {
            1 { Invoke-NormalFileAccess }
            2 { Invoke-NormalNetworkAccess }
            3 { Invoke-NormalLogon }
            4 { Invoke-NormalFileAccess; Invoke-NormalFileAccess }
        }
        $count++
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 150)
    }

    # False positive: AV scan at 02:30 (even days)
    if ($current_date.Day % 2 -eq 0) {
        Set-Date -Date $current_date.Date.AddHours(2).AddMinutes(30) | Out-Null
        Invoke-FalsePositive_AVScan
    }

    # False positive: Auth failure at 08:50 (multiples of 3)
    if ($current_date.Day % 3 -eq 0) {
        Set-Date -Date $current_date.Date.AddHours(8).AddMinutes(50) | Out-Null
        Invoke-FalsePositive_AuthFail
    }

    Write-Host "  Done: $count actions"
}

# [3] Restore system time
Write-Host "`n[3] Restoring system time..."
Set-Date -Date $REAL_TIME | Out-Null
Write-Host "  Restored: $($REAL_TIME.ToString('yyyy-MM-dd HH:mm:ss'))"

# [4] Cleanup all traces
Write-Host "`n[4] Cleaning up traces..."

$download_path = "$env:USERPROFILE\Downloads"
@(
    "$download_path\Generate-user-EventLogs.ps1",
    "$download_path\Generate-EventLogs-v4.ps1"
) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
Write-Host "  Download files deleted"

Clear-History
Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
Write-Host "  PowerShell history deleted"

$edge_paths = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History-journal",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Download Service\Files"
)
foreach ($path in $edge_paths) {
    Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
}
Write-Host "  Edge history deleted"

Remove-Item "C:\Windows\Prefetch\POWERSHELL*" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Prefetch\GENERATE*"   -Force -ErrorAction SilentlyContinue
Write-Host "  Prefetch deleted"

Start-Process "cmd.exe" -ArgumentList "/c ping 127.0.0.1 -n 2 > nul & del /f /q `"$($MyInvocation.MyCommand.Path)`"" -WindowStyle Hidden
Write-Host "  Script self-deleted"

Write-Host "`n======================================"
Write-Host " All done!"
Write-Host " Logs: May 14 ~ 21 generated"
Write-Host " Traces: All cleaned"
Write-Host " Ready for attack simulation"
Write-Host "======================================"
