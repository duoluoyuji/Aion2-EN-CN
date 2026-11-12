@echo off
chcp 936 >nul 2>&1
title AION2 英文入口汉化 · 一键诊断
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aion2Diag.ps1"
echo.
pause
