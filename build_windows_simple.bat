@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Simple Windows build script for Kelivo
REM Goals:
REM 1) Keep window open on error for review
REM 2) Report any error clearly (no silent success)

REM Switch to script directory; fail fast if not accessible
pushd "%~dp0" 1>nul 2>nul
if errorlevel 1 (
  echo [ERROR] Failed to change to script directory: "%~dp0"
  echo Please run this script from a valid local drive.
  goto :PAUSE_AND_EXIT_2
)
set "PUSHDONE=1"

set "PS=powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass"

if not exist "scripts\build_windows.ps1" (
  echo [ERROR] Missing script: scripts\build_windows.ps1
  echo Make sure you are at the repository root.
  goto :PAUSE_AND_EXIT_3
)

echo ========================================
echo Building Kelivo for Windows
echo ========================================
echo.

%PS% -File "scripts\build_windows.ps1"
set "EXITCODE=%ERRORLEVEL%"

REM Secondary validation to avoid silent failures
set "EXE=build\windows\x64\runner\Release\kelivo.exe"
set "ZIP=dist\kelivo-windows-x64.zip"

if "%EXITCODE%"=="0" (
  if not exist "%EXE%" (
    echo [ERROR] Build reported success, but executable not found: "%EXE%"
    set "EXITCODE=10"
  ) else (
    if not exist "%ZIP%" (
      echo [WARN] Archive not found: "%ZIP%" (you may zip the folder later)
    )
  )
)

if "%EXITCODE%"=="0" (
  echo.
  echo ========================================
  echo Build completed successfully!
  echo ========================================
  echo Output files:
  echo   - Executable: %EXE%
  echo   - Portable:   dist\kelivo-windows-x64\
  echo   - Package:    %ZIP%
  echo.
  set "FINAL=%EXITCODE%"
) else (
  echo.
  echo ========================================
  echo Build failed with code %EXITCODE%.
  echo See messages above for details.
  echo ========================================
  echo.
  set "FINAL=%EXITCODE%"
)

goto :PAUSE_AND_EXIT

:PAUSE_AND_EXIT_2
set "FINAL=2"
goto :PAUSE_AND_EXIT

:PAUSE_AND_EXIT_3
set "FINAL=3"
goto :PAUSE_AND_EXIT

:PAUSE_AND_EXIT
echo Press any key to close this window...
pause >nul
if defined PUSHDONE (
  popd
)
exit /b %FINAL%
