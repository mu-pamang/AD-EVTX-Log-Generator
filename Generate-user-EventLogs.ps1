# ============================================================
# WIN10-CLIENT 정상 + 오탐 로그 생성 스크립트 v3
# 목표: 2,000~3,000개 / 14일~21일 분산
# ============================================================

# ── 0. 감사 정책 활성화 ──────────────────────────────────────
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable
auditpol /set /subcategory:"File System" /success:enable /failure:enable
auditpol /set /subcategory:"Detailed File Share" /success:enable
auditpol /set /subcategory:"Process Creation" /success:enable

# ── 1. 실제 파일 목록 수집 ───────────────────────────────────
$userProfile = $env:USERPROFILE
$scanPaths   = @("$userProfile\Documents","$userProfile\Desktop","$userProfile\Downloads")

$discoveredFiles = @()
foreach ($p in $scanPaths) {
    if (Test-Path $p) {
        $discoveredFiles += Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue
    }
}

# 파일 부족 시 폴백
if ($discoveredFiles.Count -lt 5) {
    $basePath = "$userProfile\Documents"
    @("Q1_report.xlsx","budget_2024.xlsx","meeting_notes.docx",
      "project_plan.docx","HR_list.xlsx","client_contact.xlsx") | ForEach-Object {
        Set-Content "$basePath\$_" -Value ("dummy content " * 100) -Force
    }
    $discoveredFiles = Get-ChildItem $basePath -Recurse -File
}
Write-Host "[+] 파일 $($discoveredFiles.Count)개 기반으로 로그 생성"

# ── 2. XML 이벤트 주입 헬퍼 ─────────────────────────────────
function Write-EventXml {
    param($EventID, $TimeStamp, $Data)
    $xml = @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <Provider Name="Microsoft-Windows-Security-Auditing"/>
    <EventID>$EventID</EventID>
    <TimeCreated SystemTime="$($TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z'))"/>
    <Computer>WIN10-CLIENT</Computer>
  </System>
  <EventData>$Data</EventData>
</Event>
"@
    $tmp = "$env:TEMP\evt_$(Get-Random).xml"
    $xml | Set-Content $tmp -Encoding UTF8
    wevtutil im $tmp 2>$null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

# ── 3. 날짜 루프 (14일~21일) ─────────────────────────────────
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

    Write-Host "`n[*] $($current.ToString('yyyy-MM-dd')) 처리 중..."

    # ── 정상: 출근 로그온 4624 + 퇴근 로그오프 4634 ──────────
    # 하루 2회 (출근/퇴근) × 6일 = 12개
    foreach ($loginHour in @(9, 18)) {
        $ts = $current.AddHours($loginHour).AddMinutes((Get-Random -Min 0 -Max 15))
        $eid = if ($loginHour -eq 9) { 4624 } else { 4634 }
        $data = @"
<Data Name="TargetUserName">jdoe</Data>
<Data Name="TargetDomainName">CORP</Data>
<Data Name="LogonType">2</Data>
<Data Name="IpAddress">-</Data>
"@
        Write-EventXml -EventID $eid -TimeStamp $ts -Data $data
        $total++
    }

    # ── 정상: 업무 시간 파일 접근 4663 ──────────────────────
    # 시간당 5개 × 8시간 × 6일 = 240개
    $workHours = @(9,10,11,13,14,15,16,17)
    foreach ($h in $workHours) {
        for ($n = 1; $n -le 5; $n++) {
            $ts   = $current.AddHours($h).AddMinutes((Get-Random -Min 0 -Max 59)).AddSeconds((Get-Random -Min 0 -Max 59))
            $file = ($discoveredFiles | Get-Random).FullName
            $data = @"
<Data Name="SubjectUserName">jdoe</Data>
<Data Name="SubjectDomainName">CORP</Data>
<Data Name="ObjectName">$file</Data>
<Data Name="AccessMask">0x1</Data>
"@
            Write-EventXml -EventID 4663 -TimeStamp $ts -Data $data
            $total++
        }
    }

    # ── 정상: 네트워크 공유 접근 5140 ───────────────────────
    # 하루 3회 × 6일 = 18개
    foreach ($shareHour in @(9, 13, 16)) {
        $ts = $current.AddHours($shareHour).AddMinutes((Get-Random -Min 5 -Max 30))
        $share = @("\\DC01\SYSVOL","\\DC01\NETLOGON") | Get-Random
        $data = @"
<Data Name="SubjectUserName">jdoe</Data>
<Data Name="SubjectDomainName">CORP</Data>
<Data Name="ShareName">$share</Data>
<Data Name="IpAddress">192.168.1.10</Data>
"@
        Write-EventXml -EventID 5140 -TimeStamp $ts -Data $data
        $total++
    }

    # ── 정상: 명시적 자격증명 4648 ──────────────────────────
    # 하루 2회 × 6일 = 12개
    foreach ($credHour in @(10, 14)) {
        $ts = $current.AddHours($credHour).AddMinutes((Get-Random -Min 0 -Max 30))
        $data = @"
<Data Name="SubjectUserName">jdoe</Data>
<Data Name="SubjectDomainName">CORP</Data>
<Data Name="TargetUserName">jdoe</Data>
<Data Name="TargetServerName">DC01</Data>
"@
        Write-EventXml -EventID 4648 -TimeStamp $ts -Data $data
        $total++
    }

    # ── 오탐: 새벽 백신 스캔 4663 대량 (격일) ───────────────
    # 50개 × 3일 = 150개
    if ($current.Day % 2 -eq 0) {
        $tsBase = $current.AddHours(2).AddMinutes(30)
        for ($f = 1; $f -le 50; $f++) {
            $ts   = $tsBase.AddSeconds($f * 2)
            $file = ($discoveredFiles | Get-Random).FullName
            $data = @"
<Data Name="SubjectUserName">SYSTEM</Data>
<Data Name="SubjectDomainName">NT AUTHORITY</Data>
<Data Name="ObjectName">$file</Data>
<Data Name="AccessMask">0x1</Data>
"@
            Write-EventXml -EventID 4663 -TimeStamp $ts -Data $data
            $total++
        }
        Write-Host "  [+] 새벽 백신 스캔 오탐 50개 주입"
    }

    # ── 오탐: 인증 실패 반복 4625 (3의 배수일) ──────────────
    # 20개 × 2일 = 40개
    if ($current.Day % 3 -eq 0) {
        $tsBase = $current.AddHours(8).AddMinutes(50)
        for ($a = 1; $a -le 20; $a++) {
            $ts = $tsBase.AddSeconds($a * 15)
            $data = @"
<Data Name="TargetUserName">jdoe</Data>
<Data Name="TargetDomainName">CORP</Data>
<Data Name="FailureReason">%%2313</Data>
<Data Name="IpAddress">192.168.1.50</Data>
"@
            Write-EventXml -EventID 4625 -TimeStamp $ts -Data $data
            $total++
        }
        Write-Host "  [+] 인증 실패 오탐 20개 주입"
    }

    Write-Host "  [✓] 누적 $total 개"
    $current = $current.AddDays(1)
}

Write-Host "`n[✓] 완료. 총 $total 개 이벤트 생성"