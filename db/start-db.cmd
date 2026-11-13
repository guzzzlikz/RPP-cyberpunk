@echo off
rem Starts the local MariaDB for the RPPCyber Open77 server (127.0.0.1:3306).
rem setup-db.ps1 does the work and is safe to run every time: first run on a new
rem computer downloads and sets everything up; later runs fix paths/passwords and
rem start the database if it is not running. It runs hidden: stop it with stop-db.cmd.
rem When CALLed (server\Start.cmd does), also exports OP77_DATABASE_CONNECTION
rem into the caller's environment, so the server finds the database at once.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-db.ps1"
if errorlevel 1 (
    echo [db] Database setup FAILED. See the messages above and db\data\mariadb.err
    exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0credentials.txt") do set "RPPDB_%%a=%%b"
set "OP77_DATABASE_CONNECTION=Server=127.0.0.1;Port=%RPPDB_port%;Database=%RPPDB_database%;User ID=%RPPDB_user%;Password=%RPPDB_password%;"
set "RPPDB_root="
set "RPPDB_password="
exit /b 0
