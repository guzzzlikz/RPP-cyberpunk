@echo off
rem Starts the local MariaDB for the RPPCyber Open77 server (127.0.0.1:3306).
rem Does nothing if it is already running. Log: data\<computer name>.err
tasklist /FI "IMAGENAME eq mariadbd.exe" 2>nul | find /I "mariadbd.exe" >nul
if not errorlevel 1 (
    echo MariaDB is already running.
    exit /b 0
)
if not exist "%~dp0server\bin\mariadbd.exe" (
    echo MariaDB is not installed in "%~dp0server". See db\README.md.
    exit /b 1
)
start "MariaDB" /MIN "%~dp0server\bin\mariadbd.exe" --defaults-file="%~dp0data\my.ini"
echo MariaDB started.
