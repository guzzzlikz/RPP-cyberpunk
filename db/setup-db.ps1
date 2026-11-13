# Sets up and starts the local MariaDB for the RPPCyber Open77 server.
#
# Safe to run any number of times; every step is skipped when already done:
#   1. downloads MariaDB (portable ZIP, SHA-256 verified) into db\server
#   2. initializes db\data and generates passwords into db\credentials.txt
#   3. writes db\data\my.ini for the repository's current location
#   4. starts MariaDB on 127.0.0.1:3306 (hidden; stop it with stop-db.cmd)
#   5. if the passwords in credentials.txt do not open db\data (for example a
#      data folder copied from another computer), resets them to the file's
#   6. creates the `open77` database and user
#   7. sets OP77_DATABASE_CONNECTION for the current Windows user
#
# db\server, db\data and db\credentials.txt are local to each computer (.gitignore).
param([switch]$NoStart)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Version = '11.4.8'
$Sha256 = 'ed86e93157af46317bb49161451c2ec258498a6fa8e68ca821ef1d780d855e6b'
$Url = "https://archive.mariadb.org/mariadb-$Version/winx64-packages/mariadb-$Version-winx64.zip"
$Port = 3306
$Database = 'open77'
$AppUser = 'open77'

$Db = $PSScriptRoot
$Server = Join-Path $Db 'server'
$Data = Join-Path $Db 'data'
$Ini = Join-Path $Data 'my.ini'
$ErrLog = Join-Path $Data 'mariadb.err'
$Credentials = Join-Path $Db 'credentials.txt'
$Bin = Join-Path $Server 'bin'
$Daemon = Join-Path $Bin 'mariadbd.exe'
$Client = Join-Path $Bin 'mariadb.exe'

function Step($text) { Write-Host "[db] $text" }
function Slash($path) { $path -replace '\\', '/' }
function New-Password {
    -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
}
function Read-Credentials {
    $map = @{}
    Get-Content $Credentials | ForEach-Object {
        $key, $value = $_ -split '=', 2
        if ($key) { $map[$key.Trim()] = "$value".Trim() }
    }
    foreach ($required in 'root', 'password') {
        if (-not $map[$required]) { throw "$Credentials has no '$required=' line." }
    }
    return $map
}
function Test-Listening {
    [bool](netstat -ano | Select-String "127\.0\.0\.1:$Port\s+.*LISTENING")
}
function Wait-Listening([bool]$state) {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Test-Listening) -ne $state) {
        if ((Get-Date) -gt $deadline) {
            throw "MariaDB did not $(if ($state) { 'start' } else { 'stop' }) in 30 s; see $ErrLog"
        }
        Start-Sleep -Milliseconds 500
    }
}
function Start-Daemon([string[]]$extra) {
    $arguments = @("--defaults-file=`"$Ini`"") + $extra
    # Hidden: a visible console window is easy to close by accident, and closing
    # it kills the database (CTRL_CLOSE_EVENT).
    Start-Process -FilePath $Daemon -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    Wait-Listening $true
}
function Stop-Daemon {
    Get-Process mariadbd -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like "$Server*" } |
        Stop-Process -Force
    Wait-Listening $false
}
# Runs SQL through the command-line client; returns the exit code instead of
# throwing (PowerShell 5.1 turns native stderr into terminating errors).
function Invoke-Sql([string]$user, [string]$password, [string]$sql, [switch]$Quiet) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $arguments = @('-h', '127.0.0.1', '-P', $Port, '-u', $user)
        if ($password) { $arguments += "-p$password" }
        $output = & $Client @arguments -e $sql 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        if (-not $Quiet) {
            $output | Where-Object { $_ -and $_ -notmatch '^\s*$' } | ForEach-Object { Write-Host "      $_" }
        }
        return $code
    } finally {
        $ErrorActionPreference = $previous
    }
}

# 1. MariaDB binaries -----------------------------------------------------------
if (-not (Test-Path $Daemon)) {
    $temp = Join-Path $env:TEMP "rpp-mariadb-$Version"
    New-Item -ItemType Directory -Force $temp | Out-Null
    $zip = Join-Path $temp "mariadb-$Version-winx64.zip"
    Step "downloading MariaDB $Version (~90 MB)..."
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $zip
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $Sha256) { throw "MariaDB download checksum mismatch: $actual" }
    Step 'extracting...'
    Expand-Archive $zip -DestinationPath $temp -Force
    Move-Item (Join-Path $temp "mariadb-$Version-winx64") $Server
    Remove-Item $temp -Recurse -Force
} else {
    Step 'MariaDB binaries present'
}

# 2. Data directory and passwords ----------------------------------------------
if (-not (Test-Path (Join-Path $Data 'mysql'))) {
    if (Test-Path $Data) { throw "$Data exists but is not an initialized MariaDB data directory; remove it and run again." }
    if (Test-Path $Credentials) {
        $existing = Read-Credentials
        $root, $app = $existing['root'], $existing['password']
        Step 'initializing data directory (passwords from credentials.txt)...'
    } else {
        $root, $app = (New-Password), (New-Password)
        @("root=$root", "user=$AppUser", "password=$app", "database=$Database", "host=127.0.0.1", "port=$Port") |
            Set-Content $Credentials -Encoding ASCII
        Step 'initializing data directory (new passwords in credentials.txt)...'
    }
    & (Join-Path $Bin 'mariadb-install-db.exe') "--datadir=$Data" "--password=$root" "--port=$Port" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "mariadb-install-db failed ($LASTEXITCODE)" }
} elseif (-not (Test-Path $Credentials)) {
    $root, $app = (New-Password), (New-Password)
    @("root=$root", "user=$AppUser", "password=$app", "database=$Database", "host=127.0.0.1", "port=$Port") |
        Set-Content $Credentials -Encoding ASCII
    Step 'credentials.txt was missing: new passwords generated, they will be applied below'
} else {
    Step 'data directory present'
}
$creds = Read-Credentials

# 3. my.ini for the current repository location ---------------------------------
# UTF-8 without BOM: MariaDB 10.6+ on Windows runs with the UTF-8 code page, and
# ASCII would turn a non-Latin path (C:\Users\<Cyrillic name>\...) into '???'.
$iniLines = @(
    '[mysqld]'
    "datadir=$(Slash $Data)"
    "port=$Port"
    'bind-address=127.0.0.1'
    'character-set-server=utf8mb4'
    'collation-server=utf8mb4_unicode_ci'
    "log-error=$(Slash $ErrLog)"
    '[client]'
    "port=$Port"
    "plugin-dir=$(Slash (Join-Path $Server 'lib\plugin'))"
)
[IO.File]::WriteAllLines($Ini, [string[]]$iniLines, (New-Object Text.UTF8Encoding $false))

if ($NoStart) { Step 'done (not started: -NoStart)'; exit 0 }

# 4. Start ---------------------------------------------------------------------
if (-not (Test-Listening)) {
    Step 'starting MariaDB...'
    Start-Daemon @()
}
Step "MariaDB listening on 127.0.0.1:$Port"

# 5. Make the passwords in credentials.txt valid for this data directory ---------
if ((Invoke-Sql 'root' $creds['root'] 'SELECT 1' -Quiet) -ne 0) {
    Step 'root password in credentials.txt does not open this data directory'
    Step '(was db\data copied from another computer?) resetting passwords to credentials.txt...'
    Stop-Daemon
    # Only for the reset, and only on 127.0.0.1 (bind-address in my.ini).
    Start-Daemon @('--skip-grant-tables')
    $reset = @"
FLUSH PRIVILEGES;
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '$($creds['root'])';
ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$($creds['root'])';
ALTER USER IF EXISTS 'root'@'::1' IDENTIFIED BY '$($creds['root'])';
FLUSH PRIVILEGES;
"@
    $code = Invoke-Sql 'root' '' $reset
    Stop-Daemon
    Start-Daemon @()
    if ($code -ne 0) { throw 'password reset failed' }
    if ((Invoke-Sql 'root' $creds['root'] 'SELECT 1' -Quiet) -ne 0) {
        throw 'root still cannot log in after the reset'
    }
    Step 'passwords reset'
}

# 6. Database and user ---------------------------------------------------------
$password = $creds['password']
$sql = @"
CREATE DATABASE IF NOT EXISTS ``$Database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$AppUser'@'127.0.0.1' IDENTIFIED BY '$password';
CREATE USER IF NOT EXISTS '$AppUser'@'localhost' IDENTIFIED BY '$password';
ALTER USER '$AppUser'@'127.0.0.1' IDENTIFIED BY '$password';
ALTER USER '$AppUser'@'localhost' IDENTIFIED BY '$password';
GRANT ALL PRIVILEGES ON ``$Database``.* TO '$AppUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ``$Database``.* TO '$AppUser'@'localhost';
FLUSH PRIVILEGES;
"@
if ((Invoke-Sql 'root' $creds['root'] $sql) -ne 0) { throw 'creating the database/user failed' }
if ((Invoke-Sql $AppUser $password "USE ``$Database``; SELECT 1" -Quiet) -ne 0) {
    throw "user '$AppUser' cannot log in"
}
Step "database '$Database' and user '$AppUser' ready (login checked)"

# 7. Connection string for the Open77 server -----------------------------------
$connection = "Server=127.0.0.1;Port=$Port;Database=$Database;User ID=$AppUser;Password=$password;"
[Environment]::SetEnvironmentVariable('OP77_DATABASE_CONNECTION', $connection, 'User')
$env:OP77_DATABASE_CONNECTION = $connection
Step 'OP77_DATABASE_CONNECTION set for this Windows user'
Step 'done'
