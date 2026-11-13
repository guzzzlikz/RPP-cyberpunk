@echo off
rem Starts the local MariaDB for the RPPCyber Open77 server (127.0.0.1:3306).
rem First run on a new computer: downloads and sets everything up (setup-db.ps1).
rem When CALLed (server\Start.cmd does), also exports OP77_DATABASE_CONNECTION
rem into the caller's environment, so the server finds the database at once.

if not exist "%~dp0server\bin\mariadbd.exe" goto setup
if not exist "%~dp0data\mysql" goto setup
if not exist "%~dp0credentials.txt" goto setup

tasklist /FI "IMAGENAME eq mariadbd.exe" 2>nul | find /I "mariadbd.exe" >nul
if not errorlevel 1 (
    echo [db] MariaDB is already running.
    goto connection
)
rem Refresh my.ini paths (the repository may have moved), then start.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-db.ps1" -NoStart >nul
start "MariaDB" /MIN "%~dp0server\bin\mariadbd.exe" --defaults-file="%~dp0data\my.ini"
echo [db] MariaDB started.
goto connection

:setup
echo [db] First run: setting up the local database...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-db.ps1"
if errorlevel 1 (
    echo [db] Database setup FAILED. See the messages above.
    exit /b 1
)

:connection
for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0credentials.txt") do set "RPPDB_%%a=%%b"
set "OP77_DATABASE_CONNECTION=Server=127.0.0.1;Port=%RPPDB_port%;Database=%RPPDB_database%;User ID=%RPPDB_user%;Password=%RPPDB_password%;"
set "RPPDB_root="
set "RPPDB_password="
exit /b 0
