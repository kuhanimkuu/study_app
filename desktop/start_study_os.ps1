# Launches Study OS fully locally: makes sure PostgreSQL is running, starts
# the FastAPI backend on 127.0.0.1:8000 (unless one is already listening),
# opens the desktop app, and stops the backend again when the app closes
# (only if this script was the one that started it).
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $repo 'frontend\build\windows\x64\runner\Release\study_os_frontend.exe'
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

Add-Type -AssemblyName PresentationFramework
function Fail($msg) {
    [System.Windows.MessageBox]::Show($msg, 'Study OS', 'OK', 'Error') | Out-Null
    exit 1
}

if (-not (Test-Path $exe)) { Fail "Desktop app not built yet.`nRun desktop\build_desktop.ps1 first." }

# PostgreSQL (installed as an auto-start service; start it if it's stopped).
$pg = Get-Service 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pg -and $pg.Status -ne 'Running') {
    try { Start-Service $pg.Name } catch { Fail "PostgreSQL service '$($pg.Name)' is stopped and couldn't be started:`n$_" }
}

function Test-Backend {
    try { Invoke-WebRequest 'http://127.0.0.1:8000/api/health' -UseBasicParsing -TimeoutSec 2 | Out-Null; $true } catch { $false }
}

$backend = $null
if (-not (Test-Backend)) {
    $backend = Start-Process python `
        -ArgumentList '-m', 'uvicorn', 'server.main:app', '--host', '127.0.0.1', '--port', '8000' `
        -WorkingDirectory $repo -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logDir 'backend.out.log') `
        -RedirectStandardError (Join-Path $logDir 'backend.err.log')
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Backend)) {
        if ($backend.HasExited) { Fail "Backend exited during startup.`nSee $logDir\backend.err.log" }
        if ((Get-Date) -gt $deadline) { Stop-Process -Id $backend.Id -Force; Fail "Backend didn't start within 90s.`nSee $logDir\backend.err.log" }
        Start-Sleep -Milliseconds 500
    }
}

$app = Start-Process $exe -WorkingDirectory (Split-Path $exe) -PassThru
$app.WaitForExit()

if ($backend -and -not $backend.HasExited) {
    # uvicorn may have spawned children; kill the whole tree.
    taskkill /PID $backend.Id /T /F | Out-Null
}
