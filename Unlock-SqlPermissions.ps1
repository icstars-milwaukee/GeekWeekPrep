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

$user    = "$env:USERDOMAIN\$env:USERNAME"
$userSql = $user -replace "'", "''"   # escape apostrophes for SQL string literals
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

# -C : trust SQL Express's self-signed certificate (newer sqlcmd / ODBC Driver 18
#      encrypts by default and rejects it otherwise)
# -b : return a non-zero exit code when a query fails, so we can detect errors
$sqlBase = @('-S', $instance, '-E', '-C', '-b')

function Invoke-Sql {
    param([string]$Query, [switch]$Raw)
    $a = $sqlBase
    if ($Raw) { $a = $a + @('-h', '-1', '-W') }
    $a = $a + @('-Q', $Query)
    $out = & $sqlcmd @a 2>&1
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = ($out | Out-String).Trim() }
}

# Waits until SQL Server accepts connections (up to ~30 seconds)
function Wait-ForSql {
    for ($i = 0; $i -lt 15; $i++) {
        if ((Invoke-Sql -Query "SELECT 1" -Raw).Ok) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

$granted      = $false   # the student's own account was added
$usedFallback = $false   # the local Administrators group was added instead

try {
    Write-Host "[1/4] Stopping SQL Server..."
    net stop $service | Out-Null

    Write-Host "[2/4] Starting SQL Server in single-user mode..."
    net start $service /m"SQLCMD" | Out-Null

    if (-not (Wait-ForSql)) {
        Write-Host "Could not connect to SQL Server in single-user mode." -ForegroundColor Red
    }
    else {
        Write-Host "[3/4] Granting sysadmin to $user..."
        $r = Invoke-Sql -Query "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$userSql') CREATE LOGIN [$user] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [$user];"
        if ($r.Ok) {
            $granted = $true
        }
        else {
            Write-Host $r.Output
            Write-Host "Could not add $user directly (common on work/school AzureAD laptops)." -ForegroundColor Yellow
            Write-Host "Trying the local Administrators group instead..." -ForegroundColor Yellow
            $r2 = Invoke-Sql -Query "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'BUILTIN\Administrators') CREATE LOGIN [BUILTIN\Administrators] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [BUILTIN\Administrators];"
            if ($r2.Ok) { $usedFallback = $true } else { Write-Host $r2.Output }
        }
    }

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
Wait-ForSql | Out-Null

if ($granted) {
    $check = Invoke-Sql -Query "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin', N'$userSql');" -Raw
    if ($check.Output -eq '1') {
        Write-Host ""
        Write-Host "SUCCESS! $user now has full permissions on SQL Server." -ForegroundColor Green
        Write-Host "Open SQL Server Management Studio, connect to $instance, and run your script."
        Read-Host "Press Enter to close"
        exit 0
    }
}
elseif ($usedFallback) {
    $check = Invoke-Sql -Query "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin', N'BUILTIN\Administrators');" -Raw
    if ($check.Output -eq '1') {
        Write-Host ""
        Write-Host "SUCCESS (with one extra step)!" -ForegroundColor Green
        Write-Host "Your laptop's administrators now have full permissions on SQL Server." -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT: always open SQL Server Management Studio this way:" -ForegroundColor Yellow
        Write-Host "  Start -> type 'SSMS' -> right-click it -> Run as administrator" -ForegroundColor Yellow
        Write-Host "Then connect to $instance and run your script."
        Read-Host "Press Enter to close"
        exit 0
    }
}

Write-Host ""
Write-Host "Something did not work - permissions are still limited." -ForegroundColor Red
Write-Host "Take a screenshot of this window and show it to your instructor."
Read-Host "Press Enter to close"
exit 1
