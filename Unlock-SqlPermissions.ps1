# GeekWeek - SQL Server Permission Unlock
# ----------------------------------------
# Fixes the "CREATE DATABASE permission denied in database 'master'" error
# in SQL Server Management Studio by granting YOUR Windows account the
# sysadmin role on your local SQLEXPRESS instance.
#
# How it works: SQL Server Express does not automatically trust computer
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

$user     = "$env:USERDOMAIN\$env:USERNAME"
$service  = 'MSSQL$SQLEXPRESS'
$instance = '.\SQLEXPRESS'

Write-Host "Unlocking SQL Server for: $user" -ForegroundColor Cyan

# --- Make sure the SQLEXPRESS service exists ---
if (-not (Get-Service $service -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: SQL Server Express (SQLEXPRESS) is not installed on this computer." -ForegroundColor Red
    Write-Host "Install SQL Server Express first, then run this script again."
    Read-Host "Press Enter to close"
    exit 1
}

# --- Make sure sqlcmd is available ---
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: sqlcmd was not found. Install SSMS or SQL command-line tools first." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

try {
    Write-Host "[1/4] Stopping SQL Server..."
    net stop $service | Out-Null

    Write-Host "[2/4] Starting SQL Server in single-user mode..."
    net start $service /m"SQLCMD" | Out-Null
    Start-Sleep -Seconds 5

    Write-Host "[3/4] Granting sysadmin to $user..."
    sqlcmd -S $instance -E -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$user') CREATE LOGIN [$user] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [$user];"

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
$check = sqlcmd -S $instance -E -h -1 -W -Q "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin');"
if ("$check".Trim() -eq '1') {
    Write-Host ""
    Write-Host "SUCCESS! $user now has full permissions on SQL Server." -ForegroundColor Green
    Write-Host "Open SQL Server Management Studio and run your script - it will work now."
} else {
    Write-Host ""
    Write-Host "Something did not work - permissions are still limited." -ForegroundColor Red
    Write-Host "Take a screenshot of this window and show it to your instructor."
}
Read-Host "Press Enter to close"
