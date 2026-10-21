# Copies the Contabo server's nightly backups down to this PC, so losing the
# server doesn't also lose its only backups (they're made on the server's
# own disk at 02:30 UTC by /usr/local/bin/study-os-backup — setup_server.sh).
#
# Each night's backup is two files: db-<stamp>.dump (pg_dump -Fc) and
# files-<stamp>.tar.gz (uploads and generated files: students' data, so keep
# the destination folder private; since 1.0.7 the server's .env is no longer
# in them, and older ones age out after 14 days). Only files not already here are
# downloaded. Copies are deleted once the backup itself (the date in its
# name) is $KeepDays days old — 14, matching the privacy policy's promise
# that backups are kept for 14 days (and that deleted accounts leave them
# within 14 days).
#
# Run by hand, or daily via the "Study OS backup pull" scheduled task:
#   powershell -NoProfile -ExecutionPolicy Bypass -File ops\pull-backups.ps1
#
# Restore a database dump (on the server, into an empty study_os database):
#   sudo -u postgres pg_restore -d study_os --clean --if-exists db-<stamp>.dump
param(
    [string]$Dest = "D:\StudyOS-backups",
    [int]$KeepDays = 14,
    [string]$Server = "root@62.171.182.123",
    [int]$Port = 1257,
    [string]$Key = "$env:USERPROFILE\.ssh\study_os_deploy"
)

$ErrorActionPreference = "Stop"
$ssh = "$env:SystemRoot\System32\OpenSSH\ssh.exe"
$scp = "$env:SystemRoot\System32\OpenSSH\scp.exe"
$opts = @("-i", $Key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=20")

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$log = Join-Path $Dest "pull.log"
function Log($msg) { "$(Get-Date -Format s)  $msg" | Tee-Object -FilePath $log -Append }

try {
    $remote = & $ssh @opts -p $Port $Server "ls /var/backups/study_os"
    if ($LASTEXITCODE -ne 0) { throw "couldn't list the server's backups (ssh exit $LASTEXITCODE)" }

    $cutoff = (Get-Date).Date.AddDays(-$KeepDays)
    $new = 0
    foreach ($name in $remote) {
        if ($name -notmatch '^(db|files)-(\d{4}-\d{2}-\d{2})-[0-9]+\.(dump|tar\.gz)$') { continue }
        # Don't fetch one the server hasn't pruned yet but we'd delete anyway.
        if ([datetime]::ParseExact($Matches[2], 'yyyy-MM-dd', $null) -lt $cutoff) { continue }
        $target = Join-Path $Dest $name
        if (Test-Path $target) { continue }
        $part = "$target.part"
        & $scp @opts -P $Port "${Server}:/var/backups/study_os/$name" $part
        if ($LASTEXITCODE -ne 0) { throw "download of $name failed (scp exit $LASTEXITCODE)" }
        Move-Item -Force $part $target
        $new++
    }

    foreach ($f in Get-ChildItem $Dest -File) {
        if ($f.Name -match '^(db|files)-(\d{4}-\d{2}-\d{2})-') {
            if ([datetime]::ParseExact($Matches[2], 'yyyy-MM-dd', $null) -lt $cutoff) { Remove-Item -Force $f.FullName }
        }
    }

    $latest = Get-ChildItem $Dest -Filter "db-*.dump" | Sort-Object Name | Select-Object -Last 1
    Log "ok: $new new file(s); newest database backup $($latest.Name)"
} catch {
    Log "FAILED: $_"
    exit 1
}
