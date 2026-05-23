# Windows Event Log Generator - WIN10-CLIENT v9 Final
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

# [추가] Normal: 4624 Type2 + 4634 - Start-Process runas style
function Invoke-NormalLogonLogoff {
    # Start-Process with credential triggers 4624 Type2 on local session
    $secPwd = ConvertTo-SecureString "qwer1234!" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("CORP\jdoe", $secPwd)
    try {
        $proc = Start-Process "cmd.exe" -ArgumentList "/c whoami" `
            -Credential $cred -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            Start-Sleep -Seconds 2
            $proc.CloseMainWindow() | Out-Null
        }
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

# [추가] False Positive 3: Windows Update pattern
function Invoke-FalsePositive_WindowsUpdate {
    Write-Host "  [FP] Windows Update pattern..."
    # COM object triggers real WU search activity in System log
    try {
        $wu = New-Object -ComObject Microsoft.Update.Session
        $searcher = $wu.CreateUpdateSearcher()
        $searcher.BeginSearch("IsInstalled=0", $null, $null) | Out-Null
    } catch {}
    # Write to Application log to simulate WU install event EID 19
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Windows Update"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "EventMessageFile" `
            -Value "C:\Windows\System32\wevtapi.dll" -Force | Out-Null
    }
    Write-EventLog -LogName Application -Source "Windows Update" `
        -EventId 19 -EntryType Information `
        -Message "Installation Successful: Windows successfully installed the following update: KB5034441" `
        -ErrorAction SilentlyContinue
}

Write-Host "======================================"
Write-Host " Event Log Generator - WIN10-CLIENT v9 Final"
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

    # Windows Update (last 3 days of period)
    if ($day -ge ($DAYS_BEFORE - 3)) { Invoke-FalsePositive_WindowsUpdate }

    Write-Host "  Done: $count actions"
}

# [3] Cleanup
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
