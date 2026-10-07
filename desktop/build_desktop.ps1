# Builds the Study OS Windows desktop app, pointed at the backend running
# on this PC (http://127.0.0.1:8000), then (re)creates the desktop shortcut.
#   powershell -ExecutionPolicy Bypass -File desktop\build_desktop.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $repo 'frontend')
try {
    flutter build windows --release --dart-define=STUDY_OS_BASE_URL=http://127.0.0.1:8000
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
} finally { Pop-Location }

$exe = Join-Path $repo 'frontend\build\windows\x64\runner\Release\study_os_frontend.exe'
$launcher = Join-Path $PSScriptRoot 'start_study_os.ps1'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Study OS.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
$lnk.WorkingDirectory = $repo
$lnk.IconLocation = "$exe,0"
$lnk.Description = 'Study OS (runs the backend locally)'
$lnk.Save()
Write-Host "Built: $exe"
Write-Host "Shortcut: $shortcutPath"
