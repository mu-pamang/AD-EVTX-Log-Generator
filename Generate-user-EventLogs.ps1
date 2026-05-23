# WIN10-CLIENT Log Generation Script v5
# Audit policy via registry (no auditpol subcategory)

# Enable audit policy via registry
$auditKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
Set-ItemProperty -Path $auditKey -Name "SCENoApplyLegacyAuditPolicy" -Value 0 -ErrorAction SilentlyContinue

$polKey = "HKLM:\SECURITY\Policy\PolAdtEv"
# Use secedit instead
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
Write-Host "[+] Audit policy configured via secedit"

# Scan actual files
$userProfile = $env:USERPROFILE
$scanPaths = @("$userProfile\Documents", "$userProfile\Desktop", "$userProfile\Downloads")

$discoveredFiles = @()
foreach ($p in $scanPaths) {
    if (Test-Path $p) {
        $discoveredFiles += Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue
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

# XML Event Injection Helper
function Write-EventXml {
    param($EventID, $TimeStamp, $Data)
    $tsStr = $TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z')
    $xml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Microsoft-Windows-Security-Auditing'/><EventID>$EventID</EventID><TimeCreated SystemTime='$tsStr'/><Computer>WIN10-CLIENT</Computer></System><EventData>$Data</EventData></Event>"
    $tmp = "$env:TEMP\evt_$(Get-Random).xml"
    $xml | Set-Content $tmp -Encoding UTF8
    wevtutil im $tmp 2>$null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

# Date loop Jan 14~21
$startDate = [datetime]"2025-01-14"
$endDate   = [datetime]"2025-01-21"
$current   = $startDate
$total     = 0

while ($current -le $endDate) {
    $dow = $current.DayOfWeek
    if ($dow -eq "Saturday" -or $dow -eq "Sunday") {
        $current = $current.AddDays(1)
        continue
    }

    Write-Host "`n[*] Processing $($current.ToString('yyyy-MM-dd'))..."

    # Normal: Logon 4624 + Logoff 4634
    foreach ($loginHour in @(9, 18)) {
        $ts = $current.AddHours($loginHour).AddMinutes((Get-Random -Minimum 0 -Maximum 15))
        $eid = if ($loginHour -eq 9) { 4624 } else { 4634 }
        $data = "<Data Name='TargetUserName'>jdoe</Data><Data Name='TargetDomainName'>CORP</Data><Data Name='LogonType'>2</Data><Data Name='IpAddress'>-</Data>"
        Write-EventXml -EventID $eid -TimeStamp $ts -Data $data
        $total++
    }

    # Normal: File access 4663 (25 per hour x 8 hours)
    $workHours = @(9,10,11,13,14,15,16,17)
    foreach ($h in $workHours) {
        for ($n = 1; $n -le 25; $n++) {
            $ts   = $current.AddHours($h).AddMinutes((Get-Random -Minimum 0 -Maximum 59)).AddSeconds((Get-Random -Minimum 0 -Maximum 59))
            $file = ($discoveredFiles | Get-Random).FullName
            $data = "<Data Name='SubjectUserName'>jdoe</Data><Data Name='SubjectDomainName'>CORP</Data><Data Name='ObjectName'>$file</Data><Data Name='AccessMask'>0x1</Data>"
            Write-EventXml -EventID 4663 -TimeStamp $ts -Data $data
            $total++
        }
    }

    # Normal: Network share 5140 (3 per day)
    foreach ($shareHour in @(9, 13, 16)) {
        $ts = $current.AddHours($shareHour).AddMinutes((Get-Random -Minimum 5 -Maximum 30))
        $share = @("\\DC01\SYSVOL","\\DC01\NETLOGON") | Get-Random
        $data = "<Data Name='SubjectUserName'>jdoe</Data><Data Name='SubjectDomainName'>CORP</Data><Data Name='ShareName'>$share</Data><Data Name='IpAddress'>192.168.1.10</Data>"
        Write-EventXml -EventID 5140 -TimeStamp $ts -Data $data
        $total++
    }

    # Normal: Explicit credential 4648 (2 per day)
    foreach ($credHour in @(10, 14)) {
        $ts = $current.AddHours($credHour).AddMinutes((Get-Random -Minimum 0 -Maximum 30))
        $data = "<Data Name='SubjectUserName'>jdoe</Data><Data Name='SubjectDomainName'>CORP</Data><Data Name='TargetUserName'>jdoe</Data><Data Name='TargetServerName'>DC01</Data>"
        Write-EventXml -EventID 4648 -TimeStamp $ts -Data $data
        $total++
    }

    # False Positive: AV scan 4663 burst at 02:30 (even days)
    if ($current.Day % 2 -eq 0) {
        $tsBase = $current.AddHours(2).AddMinutes(30)
        for ($f = 1; $f -le 100; $f++) {
            $ts   = $tsBase.AddSeconds($f * 2)
            $file = ($discoveredFiles | Get-Random).FullName
            $data = "<Data Name='SubjectUserName'>SYSTEM</Data><Data Name='SubjectDomainName'>NT AUTHORITY</Data><Data Name='ObjectName'>$file</Data><Data Name='AccessMask'>0x1</Data>"
            Write-EventXml -EventID 4663 -TimeStamp $ts -Data $data
            $total++
        }
        Write-Host "  [+] AV scan false positive: 100 events"
    }

    # False Positive: Auth failure 4625 at 08:50 (multiples of 3)
    if ($current.Day % 3 -eq 0) {
        $tsBase = $current.AddHours(8).AddMinutes(50)
        for ($a = 1; $a -le 20; $a++) {
            $ts = $tsBase.AddSeconds($a * 15)
            $data = "<Data Name='TargetUserName'>jdoe</Data><Data Name='TargetDomainName'>CORP</Data><Data Name='FailureReason'>%%2313</Data><Data Name='IpAddress'>192.168.1.50</Data>"
            Write-EventXml -EventID 4625 -TimeStamp $ts -Data $data
            $total++
        }
        Write-Host "  [+] Auth failure false positive: 20 events"
    }

    Write-Host "  [OK] Cumulative total: $total"
    $current = $current.AddDays(1)
}

Write-Host "`n[DONE] Total events generated: $total"
