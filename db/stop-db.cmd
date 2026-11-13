@echo off
rem Cleanly stops the local MariaDB. Reads the root password from credentials.txt.
for /f "tokens=1,* delims==" %%a in ('findstr /b "root=" "%~dp0credentials.txt"') do set "ROOTPW=%%b"
"%~dp0server\bin\mariadb-admin.exe" -h 127.0.0.1 -u root -p%ROOTPW% shutdown
set "ROOTPW="
