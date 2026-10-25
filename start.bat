@echo off
setlocal EnableExtensions

REM Windows launcher for this repo, the counterpart of start.sh.
REM Runs the checked-in build output by default; use "start.bat rebuild" to force a
REM full Web + Core rebuild, and "start.bat status" to print the resolved settings.
REM
REM The NapCat endpoint and internal token are injected here because the backend does
REM not read .env: there is no dotenv dependency, and .env is only interpolated by
REM docker compose. A native "node core\client.js" process would otherwise fall back to
REM the container hostname napcat, which does not resolve on the host.
REM
REM Keep this file ASCII only. cmd reads batch files in the console codepage, so UTF-8
REM comments can be decoded into bytes that swallow quotes and break the next lines.

cd /d "%~dp0"

set "BOT_TITLE=QQ_FARM_BOT_LI"
set "WEB_DIST=%~dp0web\dist\index.html"
set "CORE_ENTRY=%~dp0core\client.js"
set "CORE_RUNTIME=%~dp0core\dist\runtime\runtime-engine.js"

REM The 404 instance owns 3007, so this repo listens on 3008 unless ADMIN_PORT is set.
if not defined ADMIN_PORT set "ADMIN_PORT=3008"

REM NapCat runs as one shared WSLC container bound to 127.0.0.1:6099 only.
REM Its token file is written on first start into data\napcat\auth\token next to the repos.
set "NAPCAT_AUTH_DIR=%~dp0..\data\napcat\auth"
set "NAPCAT_WEBUI_URL=http://127.0.0.1:6099/api"
set "NAPCAT_OPENAUTH_URL=http://127.0.0.1:6099/plugin/qq-miniapp-openauth/api"
for %%I in ("%NAPCAT_AUTH_DIR%\token") do set "NAPCAT_TOKEN_FILE=%%~fI"

if /I "%~1"=="status" goto :print_status

echo [INFO] NapCat endpoint : %NAPCAT_WEBUI_URL%
echo [INFO] NapCat token file: %NAPCAT_TOKEN_FILE%
if exist "%NAPCAT_TOKEN_FILE%" (
    echo [OK] NapCat token file found.
) else (
    echo [WARN] NapCat token file missing. Start the container first: in qq-farm-bot-404 run "napcat-wslc.ps1 up".
)

REM Refuse to start a second instance: two processes would share core\data.
for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":%ADMIN_PORT% " ^| findstr "LISTENING"') do (
    echo [INFO] li is already running. PID=%%P PORT=%ADMIN_PORT%
    echo [INFO] Stop that instance first, then run this script again.
    pause
    exit /b 0
)

if /I "%~1"=="rebuild" (
    echo [INFO] Forced rebuild requested...
    call :ensure_pnpm || exit /b 1
    call :ensure_deps || exit /b 1
    call :build_all || exit /b 1
) else (
    if exist "%WEB_DIST%" if exist "%CORE_ENTRY%" if exist "%CORE_RUNTIME%" (
        echo [INFO] Using checked-in build output; no compiler will run.
        echo [INFO] This repo tracks core\dist, core\client.js and web\dist: run "start.bat rebuild" after source changes.
    ) else (
        echo [INFO] Build output incomplete, building once...
        call :ensure_pnpm || exit /b 1
        call :ensure_deps || exit /b 1
        call :build_all || exit /b 1
    )
)

if not exist "%CORE_ENTRY%" (
    echo [ERROR] %CORE_ENTRY% not found. Run "start.bat rebuild" on a machine that can build.
    pause
    exit /b 1
)

echo [INFO] Opening li console...
start "%BOT_TITLE%" cmd /k "cd /d "%~dp0" && set ADMIN_PORT=%ADMIN_PORT% && node core\client.js"

echo [OK] Launch command sent.
echo [INFO] Panel: http://localhost:%ADMIN_PORT%
echo [INFO] QQ QR login is enabled by default and reads the NapCat values injected above.
exit /b 0

:print_status
echo == li startup plan ==
echo   panel port       : %ADMIN_PORT%
if exist "%WEB_DIST%" (echo   web output       : present) else (echo   web output       : MISSING - build needed)
if exist "%CORE_ENTRY%" (echo   core entry       : present) else (echo   core entry       : MISSING - build needed)
if exist "%CORE_RUNTIME%" (echo   core runtime     : present) else (echo   core runtime     : MISSING - build needed)
if exist "%NAPCAT_TOKEN_FILE%" (echo   napcat token     : present) else (echo   napcat token     : MISSING - start the container)
echo   NAPCAT_WEBUI_URL   = %NAPCAT_WEBUI_URL%
echo   NAPCAT_OPENAUTH_URL = %NAPCAT_OPENAUTH_URL%
echo   NAPCAT_TOKEN_FILE  = %NAPCAT_TOKEN_FILE%
exit /b 0

:ensure_pnpm
set "PNPM_CMD="
where pnpm >nul 2>nul
if not errorlevel 1 (
    set "PNPM_CMD=pnpm"
    exit /b 0
)
where corepack >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Neither pnpm nor corepack was found. Install pnpm 10+ to build.
    exit /b 1
)
set "PNPM_CMD=corepack pnpm"
exit /b 0

:ensure_deps
if not exist "%~dp0core\node_modules" (
    echo [INFO] Installing workspace dependencies...
    call %PNPM_CMD% install -r
    if errorlevel 1 (
        echo [ERROR] Dependency installation failed.
        exit /b 1
    )
)
exit /b 0

:build_all
echo [INFO] Building Web...
call %PNPM_CMD% -C web build
if errorlevel 1 (
    echo [ERROR] Web build failed.
    exit /b 1
)
echo [INFO] Building Core...
call %PNPM_CMD% -C core run build:ts
if errorlevel 1 (
    echo [ERROR] Core build failed.
    exit /b 1
)
exit /b 0
