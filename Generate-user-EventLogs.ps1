# Windows Event Log Generator - WIN10-CLIENT v9
# Scenario: New employee PC recently provisioned

$REAL_TIME   = Get-Date
$DAYS_BEFORE = 8
$ATTACK_DATE = [datetime]"2026-05-22"
$START_DATE  = $ATTACK_DATE.AddDays(-$DAYS_BEFORE)

# [0] Audit policy via secedit (Korean Windows compatible)
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
Write-Host "[+] Audit policy configured"

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
Write-Host "[+] Found $($discoveredFiles.Count) files"

# Normal: File access 4663
function Invoke-NormalFileAccess {
    $f = ($discoveredFiles | Get-Random).FullName
    if (Test-Path $f) { Get-Content $f -ErrorAction SilentlyContinue | Out-Null }
}

# Normal: Network share 5140
function Invoke-NormalNetworkAccess {
    foreach ($share in @("\\DC01\SYSVOL","\\DC01\NETLOGON")) {
        try { Get-ChildItem $share -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}

# Normal: Explicit credential 4648 + 5140
function Invoke-NormalLogon {
    net use \\DC01\IPC$ /user:CORP\jdoe "qwer1234!" 2>$null
    net use \\DC01\IPC$ /delete 2>$null
}

# Normal: runas style logon 4624 Type2 + 4634
function Invoke-NormalLogonLogoff {
    $cred = New-Object System.Management.Automation.PSCredential(
        "CORP\jdoe",
        (ConvertTo-SecureString "qwer1234!" -AsPlainText -Force)
    )
    try {
        $job = Start-Job -ScriptBlock { Get-ChildItem "\\DC01\SYSVOL" } -Credential $cred
        Wait-Job $job -Timeout 10 | Out-Null
        Remove-Job $job -Force | Out-Null
    } catch {}
}

# False Positive 1: AV scan - large file access burst 4663
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

# False Positive 2: Auth failure 4625 burst
function Invoke-FalsePositive_AuthFail {
    Write-Host "  [FP] Auth failure pattern..."
    for ($i = 1; $i -le 20; $i++) {
        net use \\DC01\IPC$ /user:CORP\jdoe "wrongpassword$i" 2>$null
        Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 800)
    }
    net use \\DC01\IPC$ /delete 2>$null
}

# False Positive 3: Windows Update pattern (System log + odd hour activity)
function Invoke-FalsePositive_WindowsUpdate {
    Write-Host "  [FP] Windows Update pattern..."
    # Trigger WU check to generate System/Application log entries
    try {
        $wu = New-Object -ComObject Microsoft.Update.Session
        $searcher = $wu.CreateUpdateSearcher()
        $searcher.BeginSearch("IsInstalled=0", $null, $null) | Out-Null
    } catch {}
    # Also write to Application log to simulate WU activity
    Write-EventLog -LogName Application -Source "Windows Update" `
        -EventId 19 -EntryType Information `
        -Message "Installation Successful: Windows successfully installed the following update: KB5034441" `
        -ErrorAction SilentlyContinue
}

Write-Host "======================================"
Write-Host " Event Log Generator - WIN10-CLIENT v9"
Write-Host " Period: $($START_DATE.ToString('MM/dd')) ~ $($ATTACK_DATE.AddDays(-1).ToString('MM/dd'))"
Write-Host " Scenario: New employee PC (recently provisioned)"
Write-Host "======================================"

# [1] Clear logs
Write-Host "`n[1] Clearing event logs..."
wevtutil cl Security    2>$null
wevtutil cl System      2>$null
wevtutil cl Application 2>$null
Write-Host "  Done"

# [2] Generate logs (8 rounds)
Write-Host "`n[2] Generating logs (8 rounds)..."

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $current_date = $START_DATE.AddDays($day)
    $dow = $current_date.DayOfWeek
    if ($dow -eq "Saturday" -or $dow -eq "Sunday") {
        Write-Host "`n  [SKIP] $($current_date.ToString('yyyy-MM-dd')) weekend"
        continue
    }

    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] Simulating $($current_date.ToString('yyyy-MM-dd'))..."

    $count  = 0
    $target = Get-Random -Minimum 300 -Maximum 400

    while ($count -lt $target) {
        $action = Get-Random -Minimum 1 -Maximum 5
        switch ($action) {
            1 { Invoke-NormalFileAccess }
            2 { Invoke-NormalNetworkAccess }
            3 { Invoke-NormalLogon }
            4 { Invoke-NormalFileAccess; Invoke-NormalFileAccess }
            5 { Invoke-NormalLogonLogoff }
        }
        $count++
        Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 100)
    }

    # AV scan (even days)
    if ($current_date.Day % 2 -eq 0) { Invoke-FalsePositive_AVScan }

    # Auth failure (multiples of 3)
    if ($current_date.Day % 3 -eq 0) { Invoke-FalsePositive_AuthFail }

    # Windows Update (last 2 days of period)
    if ($day -ge ($DAYS_BEFORE - 3)) { Invoke-FalsePositive_WindowsUpdate }

    Write-Host "  Done: $count actions"
}

Write-Host "`n[3] Cleaning up traces..."

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
