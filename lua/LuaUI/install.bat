@echo off
setlocal

:: TotallyLegal Widget Installer
:: Creates a directory junction from BAR's widget folder to this repo's widgets.
:: Run this once after cloning. Requires admin privileges for mklink /J.

set "SCRIPT_DIR=%~dp0"
set "WIDGET_SRC=%SCRIPT_DIR%Widgets"

:: Auto-detect BAR data directory
set "BAR_DATA="

:: Check common install locations
if exist "%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\Widgets" (
    set "BAR_DATA=%LOCALAPPDATA%\Programs\Beyond-All-Reason\data"
)
if "%BAR_DATA%"=="" if exist "%PROGRAMFILES%\Beyond-All-Reason\data\LuaUI\Widgets" (
    set "BAR_DATA=%PROGRAMFILES%\Beyond-All-Reason\data"
)
if "%BAR_DATA%"=="" if exist "%USERPROFILE%\Beyond All Reason\data\LuaUI\Widgets" (
    set "BAR_DATA=%USERPROFILE%\Beyond All Reason\data"
)

:: Allow override via argument
if not "%~1"=="" set "BAR_DATA=%~1"

if "%BAR_DATA%"=="" (
    echo ERROR: Could not find BAR data directory.
    echo.
    echo Usage: install.bat [BAR_DATA_PATH]
    echo Example: install.bat "C:\Games\BAR\data"
    echo.
    echo The data directory should contain a LuaUI\Widgets folder.
    exit /b 1
)

set "TARGET=%BAR_DATA%\LuaUI\Widgets\TotallyLegal"

echo TotallyLegal Widget Installer
echo ==============================
echo Source:  %WIDGET_SRC%
echo Target:  %TARGET%
echo.

:: Check source exists
if not exist "%WIDGET_SRC%" (
    echo ERROR: Widget source not found at %WIDGET_SRC%
    exit /b 1
)

:: Check BAR widgets folder exists
if not exist "%BAR_DATA%\LuaUI\Widgets" (
    echo ERROR: BAR widgets folder not found at %BAR_DATA%\LuaUI\Widgets
    exit /b 1
)

:: Remove existing link/folder if present
if exist "%TARGET%" (
    echo Removing existing link...
    rmdir "%TARGET%" 2>nul
    if exist "%TARGET%" (
        echo WARNING: Could not remove existing target. Is it a regular folder?
        echo Delete it manually: %TARGET%
        exit /b 1
    )
)

:: Create junction
mklink /J "%TARGET%" "%WIDGET_SRC%"
if errorlevel 1 (
    echo.
    echo ERROR: mklink failed. Try running this script as Administrator.
    exit /b 1
)

echo.
echo SUCCESS: Widgets linked.
echo Launch BAR and enable TotallyLegal widgets from the widget list.
echo.
echo To uninstall: rmdir "%TARGET%"

endlocal
