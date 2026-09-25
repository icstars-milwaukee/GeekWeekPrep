# GeekWeek - SQL Server Permission Unlock
# ----------------------------------------
# Fixes the "CREATE DATABASE permission denied in database 'master'" error
# in SQL Server Management Studio by granting YOUR Windows account the
# sysadmin role on your local SQL Server instance.
#
# How it works: SQL Server does not automatically trust computer
# administrators. This script briefly restarts SQL Server in single-user
# mode (where local admins ARE trusted), adds your account as sysadmin,
# then restarts SQL Server normally. Run time: about 30 seconds.
#
# You must be a local administrator on your own laptop. When the blue
# "Do you want to allow this app to make changes?" box appears, click Yes.

$ErrorActionPreference = 'Continue'

# --- Self-elevate: relaunch as Administrator if we aren't already ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrator rights (click Yes on the prompt)..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
    exit
}

$user = "$env:USERDOMAIN\$env:USERNAME"
Write-Host "Unlocking SQL Server for: $user" -ForegroundColor Cyan

# --- Find the SQL Server instance on this computer (any name) ---
$sqlServices = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' }
if (-not $sqlServices) {
    Write-Host "ERROR: No SQL Server instance is installed on this computer." -ForegroundColor Red
    Write-Host "Install SQL Server Express first, then run this script again."
    Read-Host "Press Enter to close"
    exit 1
}
# Prefer a running instance; otherwise take the first one found
$svc = ($sqlServices | Where-Object Status -eq 'Running' | Select-Object -First 1)
if (-not $svc) { $svc = $sqlServices | Select-Object -First 1 }
$service = $svc.Name
if ($service -eq 'MSSQLSERVER') { $instance = '.' } else { $instance = '.\' + $service.Split('$')[1] }
Write-Host "Found SQL Server instance: $instance (service: $service)"

# --- Find sqlcmd, even if it's not in PATH ---
$sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $sqlcmd) {
    $searchRoots = @("$env:ProgramFiles\Microsoft SQL Server", "${env:ProgramFiles(x86)}\Microsoft SQL Server")
    $sqlcmd = $searchRoots | Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Recurse -Filter SQLCMD.EXE -ErrorAction SilentlyContinue } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $sqlcmd) {
    Write-Host "ERROR: sqlcmd was not found. Install SQL Server Management Studio first." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}
Write-Host "Found sqlcmd: $sqlcmd"

try {
    Write-Host "[1/4] Stopping SQL Server..."
    net stop $service | Out-Null

    Write-Host "[2/4] Starting SQL Server in single-user mode..."
    net start $service /m"SQLCMD" | Out-Null
    Start-Sleep -Seconds 5

    Write-Host "[3/4] Granting sysadmin to $user..."
    & $sqlcmd -S $instance -E -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$user') CREATE LOGIN [$user] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [$user];"

    Write-Host "[4/4] Restarting SQL Server in normal mode..."
    net stop $service | Out-Null
    net start $service | Out-Null
}
finally {
    # Whatever happened, make sure SQL Server is running for the student
    if ((Get-Service $service).Status -ne 'Running') {
        net start $service | Out-Null
    }
}

# --- Verify it worked ---
Start-Sleep -Seconds 3
$check = & $sqlcmd -S $instance -E -h -1 -W -Q "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin');"
if ("$check".Trim() -eq '1') {
    Write-Host ""
    Write-Host "SUCCESS! $user now has full permissions on SQL Server." -ForegroundColor Green
    Write-Host "Open SQL Server Management Studio, connect to $instance, and run your script."
} else {
    Write-Host ""
    Write-Host "Something did not work - permissions are still limited." -ForegroundColor Red
    Write-Host "Take a screenshot of this window and show it to your instructor."
}
Read-Host "Press Enter to close"
