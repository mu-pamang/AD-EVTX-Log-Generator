# Add SACL and generate 4663 events - Append to existing logs
# Run as Administrator

$userProfile = $env:USERPROFILE
$targetPath  = "$userProfile\Documents"

# [1] Set SACL on Documents folder
Write-Host "[1] Setting SACL on $targetPath ..."
try {
    $acl = Get-Acl $targetPath
    $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
        "Everyone",
        "ReadData,WriteData,Delete",
        "ContainerInherit,ObjectInherit",
        "None",
        "Success"
    )
    $acl.AddAuditRule($auditRule)
    Set-Acl $targetPath $acl
    Write-Host "  [+] SACL set OK"
} catch {
    Write-Host "  [-] SACL failed: $_"
    exit
}

# [2] Scan files
$files = Get-ChildItem $targetPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*Add-SACL*" }

if ($files.Count -eq 0) {
    Write-Host "  [!] No files found, creating fallback files..."
    @("Q1_report.xlsx","budget_2024.xlsx","meeting_notes.docx","project_plan.docx","HR_list.xlsx") | ForEach-Object {
        Set-Content "$targetPath\$_" -Value ("dummy content " * 100) -Force
    }
    $files = Get-ChildItem $targetPath -Recurse -File
}
Write-Host "  [+] Found $($files.Count) files"

# [3] Generate 4663 by actually reading files (SACL triggers real 4663)
Write-Host "`n[2] Generating 4663 events (file read)..."
$count = 0
$target = 300

while ($count -lt $target) {
    $f = ($files | Get-Random).FullName
    if (Test-Path $f) {
        Get-Content $f -ErrorAction SilentlyContinue | Out-Null
        $count++
    }
    Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 200)
}
Write-Host "  [+] $count file access events generated"

# [4] AV scan pattern - burst 4663
Write-Host "`n[3] Generating burst 4663 (AV scan pattern)..."
$files | ForEach-Object {
    try { [System.IO.File]::ReadAllBytes($_.FullName) | Out-Null } catch {}
    Start-Sleep -Milliseconds 30
}
Write-Host "  [+] Burst complete"

Write-Host "`n[Done] 4663 events appended to existing logs (today 05/23)"
