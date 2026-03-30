@echo off
title MotoGo24 Web PHP
echo.
echo   MotoGo24 Web PHP - lokalni server
echo   ==================================
echo.
echo   Spoustim na http://localhost:8000
echo   Ctrl+C pro zastaveni
echo.
start http://localhost:8000
cd /d "%~dp0"
php -S localhost:8000
pause
