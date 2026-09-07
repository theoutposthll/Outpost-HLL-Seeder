@echo off
setlocal

REM ============================================================================
REM THE OUTPOST HLL AUTO-SEEDER - TRANSPARENT LAUNCHER - v0.24
REM ============================================================================
REM
REM Right-click this file -> Edit to inspect it in Notepad.
REM
REM The BAT and PowerShell files may keep their versioned download names.
REM Example:
REM     OutpostHLLSeeder_v0.24.bat
REM     OutpostHLLSeeder_v0.24.ps1
REM
REM This launcher finds the PowerShell file with the SAME base filename.
REM The installed canonical pair works the same way.
REM
REM No administrator privileges are requested.
REM The installed background scheduler is launched with a hidden window.
REM
REM -ExecutionPolicy Bypass is used ONLY for this PowerShell process.
REM It does NOT change the computer's permanent PowerShell execution policy.
REM It is required on systems where local script execution is disabled.
REM ============================================================================

set "PS1=%~dp0%~n0.ps1"

if not exist "%PS1%" (
    echo.
    echo ======================================================================
    echo OUTPOST HLL AUTO-SEEDER COULD NOT START
    echo ======================================================================
    echo.
    echo Matching PowerShell file was not found:
    echo   "%PS1%"
    echo.
    echo Keep the BAT and PS1 together and give them the same base filename.
    echo Example:
    echo   OutpostHLLSeeder_v0.24.bat
    echo   OutpostHLLSeeder_v0.24.ps1
    echo.
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    REM A scheduler is intentionally hidden/background. Do not leave a hidden
    REM PAUSE waiting forever if that background launch fails.
    if /I "%~1"=="-Scheduler" exit /b %RC%

    echo.
    echo ======================================================================
    echo OUTPOST HLL AUTO-SEEDER STOPPED WITH AN ERROR
    echo ======================================================================
    echo.
    echo PowerShell exit code: %RC%
    echo.
    echo If an installed error log exists, it is here:
    echo   %LOCALAPPDATA%\OutpostHLLSeeder\errors.txt
    echo.
    echo The window is being kept open so this error can be read.
    echo.
    pause
)

endlocal & exit /b %RC%
