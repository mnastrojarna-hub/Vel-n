@echo off
setlocal
cd /d "%~dp0"
title Velin

where node >nul 2>nul
if errorlevel 1 (
  echo [Velin] Node.js neni nainstalovan nebo neni v PATH.
  echo [Velin] Stahnete a nainstalujte Node.js 18+ z https://nodejs.org
  echo.
  pause
  exit /b 1
)

node start.js
set EXITCODE=%ERRORLEVEL%
if not "%EXITCODE%"=="0" (
  echo.
  echo [Velin] Velin skoncil s chybou (kod %EXITCODE%).
  pause
)
exit /b %EXITCODE%
