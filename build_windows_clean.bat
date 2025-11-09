@echo off
setlocal enabledelayedexpansion

rem ============================================
rem build_windows_clean.bat
rem Sequence:
rem   1) Change to script directory (project root)
rem   2) Check flutter in PATH
rem   3) flutter clean
rem   4) flutter pub get
rem   5) call build_windows_simple.bat and propagate its exit code
rem All paths exit via :EXIT:
rem   - popd (if pushd succeeded)
rem   - endlocal & exit /b %FINAL_EXITCODE%
rem ============================================

set "FINAL_EXITCODE=0"

rem Step 0: change to script directory
echo [INIT] Switching to script directory...
pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to change directory to script location.
    echo         Please run this script from a valid project directory.
    set "FINAL_EXITCODE=1"
    goto EXIT
)
echo [OK] Current directory: %CD%

rem Step 1: check flutter command
echo [1/3] Checking for 'flutter' in PATH...
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 'flutter' command not found in PATH.
    echo         Please ensure Flutter is installed and added to PATH.
    set "FINAL_EXITCODE=2"
    goto EXIT
)
echo [OK] flutter found.

rem Step 2: flutter clean
echo [2/3] Running 'flutter clean'...
flutter clean
set "CLEAN_EXITCODE=%errorlevel%"
if not "%CLEAN_EXITCODE%"=="0" (
    echo [ERROR] 'flutter clean' failed with code %CLEAN_EXITCODE%.
    set "FINAL_EXITCODE=3"
    goto EXIT
)
echo [OK] 'flutter clean' completed successfully.

rem Step 3: flutter pub get
echo [3/3] Running 'flutter pub get'...
flutter pub get
set "PUBGET_EXITCODE=%errorlevel%"
if not "%PUBGET_EXITCODE%"=="0" (
    echo [ERROR] 'flutter pub get' failed with code %PUBGET_EXITCODE%.
    set "FINAL_EXITCODE=4"
    goto EXIT
)
echo [OK] 'flutter pub get' completed successfully.

rem Step 4: call build_windows_simple.bat
echo [BUILD] Running 'build_windows_simple.bat'...
call "%~dp0build_windows_simple.bat"
set "BUILD_EXITCODE=%errorlevel%"
set "FINAL_EXITCODE=%BUILD_EXITCODE%"

if "%BUILD_EXITCODE%"=="0" (
    echo [OK] 'build_windows_simple.bat' completed successfully with code %BUILD_EXITCODE%.
) else (
    echo [ERROR] 'build_windows_simple.bat' failed with code %BUILD_EXITCODE%.
)

goto EXIT

:EXIT
rem Ensure we have a final exit code
if not defined FINAL_EXITCODE (
    set "FINAL_EXITCODE=%errorlevel%"
    if not defined FINAL_EXITCODE set "FINAL_EXITCODE=1"
)

rem Restore original directory if pushd succeeded
popd >nul 2>&1

echo [EXIT] build_windows_clean.bat exiting with code %FINAL_EXITCODE%.
endlocal & exit /b %FINAL_EXITCODE%