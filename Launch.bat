@echo off
title FX Rate Query Tool - Bank of Taiwan
echo ============================================
echo   Bank of Taiwan Exchange Rate Query Tool
echo ============================================
echo.
echo Starting...
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0ExchangeRate.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Error code: %ERRORLEVEL%
    pause
)
