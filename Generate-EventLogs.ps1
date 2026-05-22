# ================================================
# Windows Event Log 생성기 v2 (DC01 AD 서버용)
# 용도: 공격 전 정상 로그 + 오탐 유발 로그 생성
#       시스템 시간 변경으로 실제 날짜 타임스탬프 적용
# 실행: DC01 PowerShell (관리자 권한)
# ================================================

$DOMAIN   = "HDFLAB"
$DC_IP    = "192.168.10.10"
$DAYS_BEFORE = 8        # 5월 14일 ~ 5월 21일 (8일치)
$ATTACK_DATE = [datetime]"2026-05-22"
$START_DATE  = $ATTACK_DATE.AddDays(-$DAYS_BEFORE)  # 5월 14일

# 실제 현재 시간 저장 (나중에 복원용)
$REAL_TIME = Get-Date

# 오탐 유발용 서비스 계정
$SERVICE_ACCOUNTS = @(
    "svc_backup",
    "svc_monitor",
    "svc_deploy",
    "admin_temp",
    "helpdesk01"
)

# 정상 사용자 계정
$NORMAL_USERS = @(
    "kim.jungwoo",
    "lee.minjun",
    "park.sooyeon",
    "choi.jinha",
    "jung.hyunwoo",
    "han.seoyeon",
    "yoon.jihoon",
    "lim.chaewon"
)

# ================================================
# 정상 로그 유발 함수
# ================================================
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
    $shares = @("\\$DC_IP\SYSVOL", "\\$DC_IP\NETLOGON")
    foreach ($share in $shares) {
        try { Get-ChildItem $share -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}
function Invoke-NormalPolicyQuery {
    try { Get-GPO -All | Out-Null } catch {}
}

# ================================================
# 오탐 유발 함수
# ================================================
function Invoke-FalsePositive_ServiceBot {
    Write-Host "  [오탐] 서비스 계정 봇 패턴..."
    for ($i = 0; $i -lt (Get-Random -Minimum 30 -Maximum 50); $i++) {
        foreach ($svc in $SERVICE_ACCOUNTS) {
            try { Get-ADUser -Identity $svc -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 100)
    }
}
function Invoke-FalsePositive_BackupJob {
    Write-Host "  [오탐] 백업 작업 패턴..."
    try {
        Get-ADUser -Filter * -Properties * | Out-Null
        Get-ADComputer -Filter * -Properties * | Out-Null
        Get-ADGroup -Filter * -Properties * | Out-Null
    } catch {}
}
function Invoke-FalsePositive_Scanner {
    Write-Host "  [오탐] 외주 점검 스캐너 패턴..."
    $scan_targets = @("Administrator", "Guest", "krbtgt", "DefaultAccount")
    foreach ($target in $scan_targets) {
        try { Get-ADUser -Identity $target -ErrorAction SilentlyContinue | Out-Null } catch {}
        Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 2000)
    }
}

# ================================================
# 메인 실행
# ================================================
Write-Host "======================================"
Write-Host " Windows Event Log 생성기 v2 시작"
Write-Host " 기간: $($START_DATE.ToString('MM/dd')) ~ $($ATTACK_DATE.AddDays(-1).ToString('MM/dd'))"
Write-Host "======================================"

# 기존 로그 클리어
Write-Host "`n[1] 기존 이벤트 로그 클리어 중..."
try {
    wevtutil cl Security
    wevtutil cl System
    wevtutil cl Application
    Write-Host "  완료"
} catch {
    Write-Host "  일부 실패 (권한 문제)"
}

# 날짜별 로그 생성
Write-Host "`n[2] 날짜별 로그 생성 시작..."

for ($day = 0; $day -lt $DAYS_BEFORE; $day++) {
    $current_date = $START_DATE.AddDays($day)
    
    # 업무 시작 시간으로 시스템 시간 변경
    $work_start = $current_date.Date.AddHours(9)
    Set-Date -Date $work_start | Out-Null
    Write-Host "`n  [$($day+1)/$DAYS_BEFORE] $($current_date.ToString('yyyy-MM-dd')) 로그 생성 중..."

    $count = 0
    $target = Get-Random -Minimum 400 -Maximum 600

    while ($count -lt $target) {
        # 시간을 조금씩 앞으로 이동 (자연스러운 흐름)
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

    # 오탐 로그 추가
    Invoke-FalsePositive_ServiceBot

    if ((Get-Random -Minimum 0 -Maximum 100) -lt 50) {
        Invoke-FalsePositive_BackupJob
    }

    # 공격 전날(5월 21일)에만 스캐너 추가
    if ($day -eq ($DAYS_BEFORE - 1)) {
        Invoke-FalsePositive_Scanner
    }

    Write-Host "  └ $count 개 완료"
}

# 시스템 시간 원래대로 복원
Write-Host "`n[3] 시스템 시간 복원 중..."
Set-Date -Date $REAL_TIME | Out-Null
Write-Host "  완료: $($REAL_TIME.ToString('yyyy-MM-dd HH:mm:ss'))"

# 흔적 삭제
Write-Host "`n[4] 실행 흔적 삭제 중..."
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
Clear-History
$hist_path = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
Remove-Item $hist_path -Force -ErrorAction SilentlyContinue
Write-Host "  완료"

Write-Host "`n======================================"
Write-Host " 완료"
Write-Host " 5월 14일 ~ 21일 로그 생성됨"
Write-Host "======================================"

# ================================================
# 공격 후 정상 로그 생성 (공격 완료 후 별도 실행)
# ================================================
<#
$post_count  = 0
$post_target = 300
Write-Host "`n[공격 후] 정상 로그 생성 중..."
while ($post_count -lt $post_target) {
    $user   = $NORMAL_USERS | Get-Random
    $action = Get-Random -Minimum 1 -Maximum 5
    switch ($action) {
        1 { Invoke-NormalADQuery -User $user }
        2 { Invoke-NormalGroupQuery }
        3 { Invoke-NormalComputerQuery }
        4 { Invoke-NormalShareAccess }
        5 { Invoke-NormalPolicyQuery }
    }
    $post_count++
    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
}
Write-Host "  └ 공격 후 정상 로그 $post_count 개 완료"
#>