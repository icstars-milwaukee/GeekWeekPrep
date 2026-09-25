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
# Accounts are matched by SID (Windows' internal account ID), not by name,
# so it works on AzureAD / work-or-school laptops where names don't resolve
# cleanly.
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

# --- Who are we? Use the real Windows identity + SID ---
$me       = [Security.Principal.WindowsIdentity]::GetCurrent()
$user     = $me.Name
$userSql  = $user -replace "'", "''"
$sidBytes = New-Object byte[] $me.User.BinaryLength
$me.User.GetBinaryForm($sidBytes, 0)
$sidHex   = '0x' + (($sidBytes | ForEach-Object { $_.ToString('X2') }) -join '')
Write-Host "Unlocking SQL Server for: $user" -ForegroundColor Cyan
Write-Host "Account SID: $($me.User.Value)" -ForegroundColor DarkGray

# S-1-5-4 = "INTERACTIVE" (everyone signed in at the keyboard). Used only as a
# fallback if the student's own account can't be added.
$interactiveSidHex = '0x010100000000000504000000'

# --- Find the SQL Server instance on this computer (any name) ---
$sqlServices = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' }
if (-not $sqlServices) {
    Write-Host "ERROR: No SQL Server instance is installed on this computer." -ForegroundColor Red
    Write-Host "Install SQL Server Express first, then run this script again."
    Read-Host "Press Enter to close"
    exit 1
}
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

# -C : trust SQL Express's self-signed certificate (sqlcmd / ODBC Driver 18+
#      encrypts by default and rejects it otherwise)
# -b : return a non-zero exit code when a query fails
$sqlBase = @('-S', $instance, '-E', '-C', '-b')

# Runs T-SQL from a temp file (safe for multi-line scripts); returns Ok + Output
function Invoke-Sql {
    param([string]$Query, [switch]$Raw)
    $tmp = Join-Path $env:TEMP ("geekweek_" + [guid]::NewGuid().ToString('N') + ".sql")
    Set-Content -Path $tmp -Value $Query -Encoding UTF8
    $a = $sqlBase + @('-i', $tmp)
    if ($Raw) { $a = $a + @('-h', '-1', '-W') }
    $out  = & $sqlcmd @a 2>&1
    $code = $LASTEXITCODE
    Remove-Item $tmp -ErrorAction SilentlyContinue
    [pscustomobject]@{ Ok = ($code -eq 0); Output = ($out | Out-String).Trim() }
}

# Waits until SQL Server accepts connections (up to ~30 seconds)
function Wait-ForSql {
    for ($i = 0; $i -lt 15; $i++) {
        if ((Invoke-Sql -Query "SELECT 1;" -Raw).Ok) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# Grants sysadmin to the login whose SID matches THIS Windows account.
# If a login with the same name but a different (stale) SID exists, it is
# removed first, because it blocks the correct one from being created.
$grantSql = @"
SET NOCOUNT ON;
DECLARE @sid varbinary(85) = $sidHex;
DECLARE @login sysname = (SELECT name FROM sys.server_principals WHERE sid = @sid);
PRINT 'SQL Server resolves this SID to: ' + ISNULL(SUSER_SNAME(@sid), '(unresolved)');
PRINT 'Existing login with this SID:    ' + ISNULL(@login, '(none)');

IF @login IS NULL
BEGIN
    DECLARE @name sysname = COALESCE(SUSER_SNAME(@sid), N'$userSql');
    IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @name)
    BEGIN
        PRINT 'Removing stale login ' + @name + ' (same name, different SID).';
        EXEC('DROP LOGIN ' + QUOTENAME(@name));
    END
    EXEC('CREATE LOGIN ' + QUOTENAME(@name) + ' FROM WINDOWS');
    SET @login = (SELECT name FROM sys.server_principals WHERE sid = @sid);
    IF @login IS NULL
        THROW 50001, 'Created a login, but its SID does not match this Windows account.', 1;
END

EXEC('ALTER LOGIN ' + QUOTENAME(@login) + ' ENABLE');
EXEC('ALTER SERVER ROLE sysadmin ADD MEMBER ' + QUOTENAME(@login));
PRINT 'Added ' + @login + ' to sysadmin.';
"@

# Fallback: grant sysadmin to INTERACTIVE (anyone signed in at this laptop).
# Looked up by SID so it works on non-English Windows too.
$fallbackSql = @"
SET NOCOUNT ON;
DECLARE @isid varbinary(85) = $interactiveSidHex;
DECLARE @iname sysname = (SELECT name FROM sys.server_principals WHERE sid = @isid);
IF @iname IS NULL
BEGIN
    SET @iname = SUSER_SNAME(@isid);
    IF @iname IS NULL THROW 50002, 'Could not resolve the INTERACTIVE group.', 1;
    EXEC('CREATE LOGIN ' + QUOTENAME(@iname) + ' FROM WINDOWS');
END
EXEC('ALTER SERVER ROLE sysadmin ADD MEMBER ' + QUOTENAME(@iname));
PRINT 'Added ' + @iname + ' to sysadmin.';
"@

$verifySql = @"
SET NOCOUNT ON;
SELECT CASE
  WHEN EXISTS (SELECT 1 FROM sys.server_role_members rm
               JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
               JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
               WHERE r.name = 'sysadmin' AND m.sid = $sidHex AND m.is_disabled = 0) THEN 'USER'
  WHEN EXISTS (SELECT 1 FROM sys.server_role_members rm
               JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
               JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
               WHERE r.name = 'sysadmin' AND m.sid = $interactiveSidHex AND m.is_disabled = 0) THEN 'INTERACTIVE'
  ELSE 'NONE' END;
"@

$diagSql = @"
SET NOCOUNT ON;
SELECT 'sysadmin member: ' + m.name + '  sid=' + CONVERT(varchar(200), m.sid, 1)
FROM sys.server_role_members rm
JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name = 'sysadmin';
SELECT 'connected as: ' + SUSER_SNAME() + '  sid=' + CONVERT(varchar(200), SUSER_SID(), 1);
"@

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
        $r = Invoke-Sql -Query $grantSql
        if ($r.Output) { Write-Host $r.Output -ForegroundColor DarkGray }
        if (-not $r.Ok) {
            Write-Host "Could not add $user directly. Trying fallback..." -ForegroundColor Yellow
            $r2 = Invoke-Sql -Query $fallbackSql
            if ($r2.Output) { Write-Host $r2.Output -ForegroundColor DarkGray }
        }
    }

    Write-Host "[4/4] Restarting SQL Server in normal mode..."
    net stop $service | Out-Null
    net start $service | Out-Null
}
finally {
    if ((Get-Service $service).Status -ne 'Running') {
        net start $service | Out-Null
    }
}

# --- Verify (checks the catalog by SID, so it reflects a normal SSMS session) ---
if (-not (Wait-ForSql)) {
    Write-Host "SQL Server did not come back up after the restart." -ForegroundColor Red
}
$v = Invoke-Sql -Query $verifySql -Raw

if ($v.Output -eq 'USER' -or $v.Output -eq 'INTERACTIVE') {
    Write-Host ""
    Write-Host "SUCCESS! $user now has full permissions on SQL Server." -ForegroundColor Green
    if ($v.Output -eq 'INTERACTIVE') {
        Write-Host "(Granted through the INTERACTIVE group because your account could not be added directly.)" -ForegroundColor DarkGray
    }
    Write-Host "Open SQL Server Management Studio, connect to $instance, and run your script."
    Read-Host "Press Enter to close"
    exit 0
}

Write-Host ""
Write-Host "Verify result: $($v.Output)" -ForegroundColor DarkGray
$d = Invoke-Sql -Query $diagSql -Raw
if ($d.Output) { Write-Host $d.Output -ForegroundColor DarkGray }
Write-Host "Something did not work - permissions are still limited." -ForegroundColor Red
Write-Host "Take a screenshot of this window and show it to your instructor."
Read-Host "Press Enter to close"
exit 1
