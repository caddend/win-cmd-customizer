@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Customize-Cmd.ps1" %*
exit /b %errorlevel%
