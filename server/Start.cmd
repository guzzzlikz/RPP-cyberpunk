@echo off
cd /d "%~dp0"
rem Local MariaDB (character editor, persistence). Skipped if not installed.
if exist "%~dp0..\db\start-db.cmd" call "%~dp0..\db\start-db.cmd"
Open77.Server.exe %*
if errorlevel 1 pause
