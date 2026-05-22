# Windows Event Log Generator v9
# Target: 10,000 logs fast
# Run on DC01 PowerShell (Administrator)

$DC_IP       = "192.168.10.10"
$DAYS_BEFORE = 8
$REAL_TIME   = Get-Date
$TARGET_TOTAL = 10000
$DAILY_TARGET = [int]($TARGET_TOTAL / $DAYS_BEFORE)  # 하루 약 1,250개

$SERVICE_ACCOUNTS = @("svc_backup","svc_monitor","svc_deploy","admin_temp","helpdesk01")
$NORMAL_USERS     = @("kim.jungwoo","lee.minjun","park.sooyeon","choi.jinha","jung.hyunwoo","han.seoyeon","yoon.jihoon","lim.chaewon","oh.jisoo","kwon.minjae","shin.yuna","bae.jungho","nam.soojin","hong.gilyong","kang.jiwon")

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
    for ($i = 0; $i -lt 30; $i++) {
        foreach ($svc in $SERVICE_ACCOUNTS) {
            try { Get-ADUser -Identity $svc -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
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
    }
}

Write-Host "======================================"
Write-Host " Event Log Generator v9"
Write-Host " Target: 10,000 logs (fast mode)"
Write-Host " Period: 05-14 ~ 05-21"
Write-Host " Estimated time: 1~2 hours"
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
Write-Host "`n[2] Generating logs (fast mode)..."
$total_count = 0

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $target_day = 14 + $day
    $work_start = Get-Date -Year 2026 -Month 5 -Day $target_day -Hour 9 -Minute 0 -Second 0

    # 시스템 시간 변경
    Set-Date -Date $work_start
    Start-Sleep -Seconds 2
    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    $count = 0

    while ($count -lt $DAILY_TARGET) {
        # 시간 조금씩 앞으로
        $seconds_to_add = Get-Random -Minimum 10 -Maximum 60
        Set-Date -Date ((Get-Date).AddSeconds($seconds_to_add))

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

        if ($count % 100 -eq 0) {
            Write-Host "    Progress: $count / $DAILY_TARGET ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
        }
    }

    # 오탐 로그
    Invoke-FalsePositive_ServiceBot
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 50) { Invoke-FalsePositive_BackupJob }
    if ($day -eq ($DAYS_BEFORE - 1)) { Invoke-FalsePositive_Scanner }

    $total_count += $count
    Write-Host "  Done: $count actions (total: $total_count)"
}

# [3] 시스템 시간 복원
Write-Host "`n[3] Restoring system time..."
Set-Date -Date $REAL_TIME
Start-Sleep -Seconds 2
Write-Host "  Restored: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# [4] 최종 로그 수 확인
Write-Host "`n[4] Final log count..."
$final_count = (Get-WinEvent -LogName Security | Measure-Object).Count
Write-Host "  Security log total: $final_count"

# [5] 흔적 삭제
Write-Host "`n[5] Cleaning up..."
$dl = "C:\Users\Administrator\Downloads"
foreach ($ver in @("","v2","v3","v4","v5","v6","v7","v8","v9")) {
    $f = if ($ver -eq "") {"Generate-EventLogs.ps1"} else {"Generate-EventLogs-$ver.ps1"}
    Remove-Item "$dl\$f" -Force -ErrorAction SilentlyContinue
}
Clear-History
Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
foreach ($p in @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History-journal",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Download Service\Files"
)) { Remove-Item $p -Force -Recurse -ErrorAction SilentlyContinue }
Remove-Item "C:\Windows\Prefetch\POWERSHELL*" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Prefetch\GENERATE*" -Force -ErrorAction SilentlyContinue
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
Write-Host "  Done"

Write-Host "`n======================================"
Write-Host " All done!"
Write-Host " Total actions: $total_count"
Write-Host " Security logs: $final_count"
Write-Host " Traces: All cleaned"
Write-Host " Ready for attack simulation"
Write-Host "======================================"
