# Windows Event Log Generator v4
# Run on DC01 PowerShell (Administrator)

$DC_IP       = "192.168.10.10"
$DAYS_BEFORE = 8
$ATTACK_DATE = [datetime]"2026-05-22"
$START_DATE  = $ATTACK_DATE.AddDays(-$DAYS_BEFORE)
$REAL_TIME   = Get-Date

$SERVICE_ACCOUNTS = @("svc_backup","svc_monitor","svc_deploy","admin_temp","helpdesk01")
$NORMAL_USERS     = @("kim.jungwoo","lee.minjun","park.sooyeon","choi.jinha","jung.hyunwoo","han.seoyeon","yoon.jihoon","lim.chaewon")

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
    Write-Host "  [FP] Service account bot pattern..."
    for ($i = 0; $i -lt (Get-Random -Minimum 30 -Maximum 50); $i++) {
        foreach ($svc in $SERVICE_ACCOUNTS) {
            try { Get-ADUser -Identity $svc -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 100)
    }
}
function Invoke-FalsePositive_BackupJob {
    Write-Host "  [FP] Backup job pattern..."
    try {
        Get-ADUser -Filter * -Properties * | Out-Null
        Get-ADComputer -Filter * -Properties * | Out-Null
        Get-ADGroup -Filter * -Properties * | Out-Null
    } catch {}
}
function Invoke-FalsePositive_Scanner {
    Write-Host "  [FP] External scanner pattern..."
    foreach ($target in @("Administrator","Guest","krbtgt","DefaultAccount")) {
        try { Get-ADUser -Identity $target -ErrorAction SilentlyContinue | Out-Null } catch {}
        Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 2000)
    }
}

Write-Host "======================================"
Write-Host " Event Log Generator v4"
Write-Host " Period: $($START_DATE.ToString('MM/dd')) ~ $($ATTACK_DATE.AddDays(-1).ToString('MM/dd'))"
Write-Host "======================================"

# [1] 기존 이벤트 로그 클리어
Write-Host "`n[1] Clearing event logs..."
try {
    wevtutil cl Security
    wevtutil cl System
    wevtutil cl Application
    Write-Host "  Done"
} catch {
    Write-Host "  Failed"
}

# [2] 날짜별 로그 생성
Write-Host "`n[2] Generating logs by date..."

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $current_date = $START_DATE.AddDays($day)
    $work_start   = $current_date.Date.AddHours(9)
    Set-Date -Date $work_start | Out-Null
    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] $($current_date.ToString('yyyy-MM-dd')) generating..."

    $count  = 0
    $target = Get-Random -Minimum 400 -Maximum 600

    while ($count -lt $target) {
        $current_time = (Get-Date).AddSeconds((Get-Random -Minimum 30 -Maximum 120))
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
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 200)
    }

    Invoke-FalsePositive_ServiceBot

    if ((Get-Random -Minimum 0 -Maximum 100) -lt 50) {
        Invoke-FalsePositive_BackupJob
    }

    if ($day -eq ($DAYS_BEFORE - 1)) {
        Invoke-FalsePositive_Scanner
    }

    Write-Host "  Done: $count actions"
}

# [3] 시스템 시간 복원
Write-Host "`n[3] Restoring system time..."
Set-Date -Date $REAL_TIME | Out-Null
Write-Host "  Restored: $($REAL_TIME.ToString('yyyy-MM-dd HH:mm:ss'))"

# [4] 흔적 삭제
Write-Host "`n[4] Cleaning up all traces..."

# 다운로드 폴더 파일 삭제
$download_path = "C:\Users\Administrator\Downloads"
$files_to_delete = @(
    "$download_path\Generate-EventLogs.ps1",
    "$download_path\Generate-EventLogs-v2.ps1",
    "$download_path\Generate-EventLogs-v3.ps1",
    "$download_path\Generate-EventLogs-v4.ps1"
)
foreach ($file in $files_to_delete) {
    Remove-Item $file -Force -ErrorAction SilentlyContinue
}
Write-Host "  Download files deleted"

# PowerShell 히스토리 삭제
Clear-History
Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
Write-Host "  PowerShell history deleted"

# Edge 브라우저 기록 삭제
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

# Prefetch 삭제 (실행 기록)
Remove-Item "C:\Windows\Prefetch\POWERSHELL*" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Prefetch\GENERATE*" -Force -ErrorAction SilentlyContinue
Write-Host "  Prefetch deleted"

# 스크립트 자기 자신 삭제
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
Write-Host "  Script self-deleted"

Write-Host "`n======================================"
Write-Host " All done!"
Write-Host " Logs: May 14 ~ 21 generated"
Write-Host " Traces: All cleaned"
Write-Host " Ready for attack simulation"
Write-Host "======================================"
