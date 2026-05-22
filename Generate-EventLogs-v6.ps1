# Windows Event Log Generator v6
# Target: 20,000~28,000 logs (small company, 20-30 users)
# Realistic time-based delay pattern
# Run on DC01 PowerShell (Administrator)

$DC_IP       = "192.168.10.10"
$DAYS_BEFORE = 8
$ATTACK_DATE = [datetime]"2026-05-22"
$START_DATE  = $ATTACK_DATE.AddDays(-$DAYS_BEFORE)
$REAL_TIME   = Get-Date

$DAILY_MIN = 2500
$DAILY_MAX = 3500

$SERVICE_ACCOUNTS = @("svc_backup","svc_monitor","svc_deploy","admin_temp","helpdesk01")
$NORMAL_USERS     = @("kim.jungwoo","lee.minjun","park.sooyeon","choi.jinha","jung.hyunwoo","han.seoyeon","yoon.jihoon","lim.chaewon","oh.jisoo","kwon.minjae","shin.yuna","bae.jungho","nam.soojin","hong.gilyong","kang.jiwon")

# Time-based delay (milliseconds)
# Peak hours: short delay / Off hours: long delay
function Get-TimeBasedDelay {
    $hour = (Get-Date).Hour
    switch ($hour) {
        {$_ -in 9,10,11}    { return Get-Random -Minimum 500  -Maximum 2000  }  # Morning peak
        {$_ -in 12,13}      { return Get-Random -Minimum 5000 -Maximum 15000 }  # Lunch break
        {$_ -in 14,15,16}   { return Get-Random -Minimum 500  -Maximum 3000  }  # Afternoon peak
        {$_ -in 17,18}      { return Get-Random -Minimum 3000 -Maximum 10000 }  # End of day
        {$_ -in 19,20,21}   { return Get-Random -Minimum 10000 -Maximum 30000 } # Evening
        {$_ -in 22,23,0,1}  { return Get-Random -Minimum 60000 -Maximum 180000} # Night
        {$_ -in 2,3,4,5}    { return Get-Random -Minimum 30000 -Maximum 60000 } # Early morning (backup)
        {$_ -in 6,7,8}      { return Get-Random -Minimum 5000  -Maximum 15000 } # Pre-work
        default              { return Get-Random -Minimum 1000  -Maximum 5000  }
    }
}

function Invoke-NormalADQuery { param([string]$User)
    try { Get-ADUser -Identity $User -Properties * | Out-Null } catch {}
}
function Invoke-NormalGroupQuery {
    try {
        Get-ADGroup -Filter * | Out-Null
        Get-ADGroupMember "Domain Admins" | Out-Null
        Get-ADGroupMember "Domain Users" | Out-Null
    } catch {}
}
function Invoke-NormalComputerQuery {
    try { Get-ADComputer -Filter * | Out-Null } catch {}
}
function Invoke-NormalShareAccess {
    foreach ($share in @("\\$DC_IP\SYSVOL","\\$DC_IP\NETLOGON")) {
        try { Get-ChildItem $share -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}
function Invoke-NormalPolicyQuery {
    try { Get-GPO -All | Out-Null } catch {}
}
function Invoke-FalsePositive_ServiceBot {
    Write-Host "  [FP] Service account bot..."
    for ($i = 0; $i -lt (Get-Random -Minimum 50 -Maximum 100); $i++) {
        foreach ($svc in $SERVICE_ACCOUNTS) {
            try { Get-ADUser -Identity $svc -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 200)
    }
}
function Invoke-FalsePositive_BackupJob {
    Write-Host "  [FP] Backup job..."
    try {
        Get-ADUser -Filter * -Properties * | Out-Null
        Get-ADComputer -Filter * -Properties * | Out-Null
        Get-ADGroup -Filter * -Properties * | Out-Null
    } catch {}
}
function Invoke-FalsePositive_Scanner {
    Write-Host "  [FP] External scanner..."
    foreach ($target in @("Administrator","Guest","krbtgt","DefaultAccount")) {
        try { Get-ADUser -Identity $target -ErrorAction SilentlyContinue | Out-Null } catch {}
        Start-Sleep -Milliseconds (Get-Random -Minimum 1000 -Maximum 3000)
    }
}

Write-Host "======================================"
Write-Host " Event Log Generator v6"
Write-Host " Target: 20,000~28,000 total logs"
Write-Host " Realistic time-based delay applied"
Write-Host " Period: $($START_DATE.ToString('MM/dd')) ~ $($ATTACK_DATE.AddDays(-1).ToString('MM/dd'))"
Write-Host " WARNING: This will take 12~24 hours"
Write-Host "======================================"

# [1] 기존 로그 클리어
Write-Host "`n[1] Clearing existing logs..."
try {
    wevtutil cl Security
    wevtutil cl System
    wevtutil cl Application
    Write-Host "  Done"
} catch {
    Write-Host "  Failed"
}

# [2] 날짜별 로그 생성
Write-Host "`n[2] Generating logs with realistic timing..."
$total_count = 0

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $current_date = $START_DATE.AddDays($day)

    # 하루 시작: 오전 8시부터
    $work_start = $current_date.Date.AddHours(8)
    Set-Date -Date $work_start | Out-Null
    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] $($current_date.ToString('yyyy-MM-dd')) generating..."

    $count  = 0
    $target = Get-Random -Minimum $DAILY_MIN -Maximum $DAILY_MAX

    while ($count -lt $target) {
        # 시간 기반 딜레이 적용
        $delay = Get-TimeBasedDelay
        Start-Sleep -Milliseconds $delay

        # 시간 자연스럽게 앞으로 이동
        $seconds_to_add = [int]($delay / 1000) + (Get-Random -Minimum 1 -Maximum 10)
        $current_time = (Get-Date).AddSeconds($seconds_to_add)
        Set-Date -Date $current_time | Out-Null

        $user   = $NORMAL_USERS | Get-Random
        $action = Get-Random -Minimum 1 -Maximum 5
        switch ($action) {
            1 { Invoke-NormalADQuery -User $user }
            2 { Invoke-NormalGroupQuery }
            3 { Invoke-NormalComputerQuery }
            4 { Invoke-NormalShareAccess }
            5 { Invoke-NormalPolicyQuery }
        }
        $count++

        # 진행 상황 100개마다 출력
        if ($count % 100 -eq 0) {
            Write-Host "    Progress: $count / $target ($(Get-Date -Format 'HH:mm:ss'))"
        }
    }

    # 오탐 로그
    Invoke-FalsePositive_ServiceBot

    if ((Get-Random -Minimum 0 -Maximum 100) -lt 50) {
        Invoke-FalsePositive_BackupJob
    }

    if ($day -eq ($DAYS_BEFORE - 1)) {
        Invoke-FalsePositive_Scanner
    }

    $total_count += $count
    Write-Host "  Done: $count actions (total: $total_count)"
}

# [3] 시스템 시간 복원
Write-Host "`n[3] Restoring system time..."
Set-Date -Date $REAL_TIME | Out-Null
Write-Host "  Restored: $($REAL_TIME.ToString('yyyy-MM-dd HH:mm:ss'))"

# [4] 최종 로그 수 확인
Write-Host "`n[4] Checking final log count..."
$final_count = (Get-WinEvent -LogName Security | Measure-Object).Count
Write-Host "  Security log total: $final_count"

# [5] 흔적 삭제
Write-Host "`n[5] Cleaning up traces..."

$download_path = "C:\Users\Administrator\Downloads"
foreach ($ver in @("","v2","v3","v4","v5","v6")) {
    $fname = if ($ver -eq "") { "Generate-EventLogs.ps1" } else { "Generate-EventLogs-$ver.ps1" }
    Remove-Item "$download_path\$fname" -Force -ErrorAction SilentlyContinue
}
Write-Host "  Download files deleted"

Clear-History
Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
Write-Host "  PowerShell history deleted"

foreach ($path in @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History-journal",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Download Service\Files"
)) {
    Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
}
Write-Host "  Edge history deleted"

Remove-Item "C:\Windows\Prefetch\POWERSHELL*" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Prefetch\GENERATE*" -Force -ErrorAction SilentlyContinue
Write-Host "  Prefetch deleted"

Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
Write-Host "  Script self-deleted"

Write-Host "`n======================================"
Write-Host " All done!"
Write-Host " Total actions: $total_count"
Write-Host " Security logs: $final_count"
Write-Host " Traces: All cleaned"
Write-Host " Ready for attack simulation"
Write-Host "======================================"
