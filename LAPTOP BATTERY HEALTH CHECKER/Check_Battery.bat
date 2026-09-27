@echo off
setlocal
cd /d "%~dp0"

title Battery Diagnostic Checker
color 0B

echo.
echo  ================================================
echo       LAPTOP BATTERY DIAGNOSTIC CHECKER
echo  ================================================
echo.
echo  Reading battery information from Windows...
echo.

if not exist "%~dp0Battery_Diagnostic.ps1" (
    echo  ERROR: Battery_Diagnostic.ps1 was not found.
    echo  Keep all files in the same folder.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Battery_Diagnostic.ps1"

if errorlevel 1 (
    echo.
    echo  Diagnostic failed. The error above contains the reason.
    echo.
    pause
    exit /b 1
)

endlocal
exit /b 0
