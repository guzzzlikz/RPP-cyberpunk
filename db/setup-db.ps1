# Sets up the local MariaDB for the RPPCyber Open77 server on this computer.
#
# Safe to run any number of times; every step is skipped when already done:
#   1. downloads MariaDB (portable ZIP, SHA-256 verified) into db\server
#   2. initializes db\data and generates passwords into db\credentials.txt
#   3. writes db\data\my.ini for the repository's current location
#   4. starts MariaDB on 127.0.0.1:3306
#   5. creates the `open77` database and user
#   6. sets OP77_DATABASE_CONNECTION for the current Windows user
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
$Credentials = Join-Path $Db 'credentials.txt'
$Bin = Join-Path $Server 'bin'

function Step($text) { Write-Host "[db] $text" }
function Slash($path) { $path -replace '\\', '/' }
function New-Password {
    -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
}
function Read-Credentials {
    $map = @{}
    Get-Content $Credentials | ForEach-Object {
        $key, $value = $_ -split '=', 2
        if ($key) { $map[$key.Trim()] = $value }
    }
    return $map
}
function Test-Listening {
    [bool](netstat -ano | Select-String "127\.0\.0\.1:$Port\s+.*LISTENING")
}

# 1. MariaDB binaries -----------------------------------------------------------
if (-not (Test-Path (Join-Path $Bin 'mariadbd.exe'))) {
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
    $root = New-Password
    $app = New-Password
    Step 'initializing data directory...'
    & (Join-Path $Bin 'mariadb-install-db.exe') "--datadir=$Data" "--password=$root" "--port=$Port" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "mariadb-install-db failed ($LASTEXITCODE)" }
    @("root=$root", "user=$AppUser", "password=$app", "database=$Database", "host=127.0.0.1", "port=$Port") |
        Set-Content $Credentials -Encoding ASCII
} elseif (-not (Test-Path $Credentials)) {
    throw "$Credentials is missing. Restore it, or delete $Data and run again (this erases the local database)."
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
    "log-error=$(Slash (Join-Path $Data 'mariadb.err'))"
    '[client]'
    "port=$Port"
    "plugin-dir=$(Slash (Join-Path $Server 'lib\plugin'))"
)
[IO.File]::WriteAllLines($Ini, [string[]]$iniLines, (New-Object Text.UTF8Encoding $false))

if ($NoStart) { Step 'done (not started: -NoStart)'; exit 0 }

# 4. Start ---------------------------------------------------------------------
if (-not (Test-Listening)) {
    Step 'starting MariaDB...'
    Start-Process -FilePath (Join-Path $Bin 'mariadbd.exe') -ArgumentList "--defaults-file=`"$Ini`"" -WindowStyle Minimized
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Listening)) {
        if ((Get-Date) -gt $deadline) { throw "MariaDB did not start; see $(Join-Path $Data 'mariadb.err')" }
        Start-Sleep -Milliseconds 500
    }
}
Step "MariaDB listening on 127.0.0.1:$Port"

# 5. Database and user ---------------------------------------------------------
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
& (Join-Path $Bin 'mariadb.exe') -h 127.0.0.1 -P $Port -u root "-p$($creds['root'])" -e $sql
if ($LASTEXITCODE -ne 0) { throw 'creating the database/user failed' }
Step "database '$Database' and user '$AppUser' ready"

# 6. Connection string for the Open77 server -----------------------------------
$connection = "Server=127.0.0.1;Port=$Port;Database=$Database;User ID=$AppUser;Password=$password;"
[Environment]::SetEnvironmentVariable('OP77_DATABASE_CONNECTION', $connection, 'User')
$env:OP77_DATABASE_CONNECTION = $connection
Step 'OP77_DATABASE_CONNECTION set for this Windows user'
Step 'done'
