@echo off
title Qwen3.8 Coder390 Q2 - NInfer Server (LAN port 8083)
REM ============================================================
REM  Double-click launcher: Qwen3.8-27B Coder390 Q2 LynnStyle
REM  3-way concurrency, 262K context window, 294912 token KV pool,
REM  vision ON, MTP d3, rk4v4 KV.
REM  Local  : http://127.0.0.1:8083/v1/chat/completions
REM  LAN    : http://<this-PC-IPv4>:8083/v1/chat/completions
REM  (Windows Firewall will ask to allow port 8083 on first LAN use)
REM ============================================================

set "DOCKEREXE=C:\Users\chenhua\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe"
if not exist "%DOCKEREXE%" set "DOCKEREXE=docker"

echo [1/3] Checking Docker engine...
"%DOCKEREXE%" ps >nul 2>&1
if not errorlevel 1 goto engine_ok
echo       Docker engine not running - starting Docker Desktop (wait up to 3 min)...
start "" "C:\Users\chenhua\AppData\Local\Programs\DockerDesktop\Docker Desktop.exe"
set TRIES=0
:wait_engine
timeout /t 5 /nobreak >nul
"%DOCKEREXE%" ps >nul 2>&1
if not errorlevel 1 goto engine_ok
set /a TRIES+=1
if %TRIES% LSS 36 goto wait_engine
echo ERROR: Docker engine did not start. Open Docker Desktop manually, wait for
echo        "Engine running", then double-click this file again.
pause
exit /b 1

:engine_ok
echo       Engine OK.

echo [2/3] Starting model container (Q2, 262K ctx, pool 360000, 3-way, vision)...
"%DOCKEREXE%" rm -f ninfer-coder390 >nul 2>&1
"%DOCKEREXE%" run -d --gpus all -p 8083:8080 --ulimit memlock=-1 --name ninfer-coder390 -v "D:\models\ninfer:/models" -v ninfer-cache:/cache ghcr.io/iamwavecut/ninfer-all:latest serve /models/Qwen3.8-27B-Coder390-EfficientThink-Q2LynnStyle-Q4MTP.ninfer --model-id qwen3.8-27b-coder390-q2-q4mtp --max-context 262144 --kv-capacity 360000 --kv-dtype rk4v4 --max-concurrency 3 --spec mtp --draft-tokens 3 --vision

echo [3/3] Waiting for model load (about 60-90 s after warm, 3 min cold)...
:wait_ready
timeout /t 10 /nobreak >nul
curl -sf http://127.0.0.1:8083/health >nul 2>&1
if errorlevel 1 goto wait_ready

echo.
echo ==============================================================
echo   MODEL IS UP - OpenAI-compatible endpoint:
echo.
echo   Local : http://127.0.0.1:8083/v1/chat/completions
echo   LAN   : http://YOUR-PC-IPv4:8083/v1/chat/completions
echo.
echo   Your IPv4 addresses:
echo.
ipconfig | findstr /C:"IPv4"
echo.
echo   model name : qwen3.8-27b-coder390-q2-q4mtp
echo   First LAN use: allow port 8083 in Windows Firewall.
echo   Stop: close this window, or  docker rm -f ninfer-coder390
echo ==============================================================
echo.
echo Streaming logs (Ctrl+C to detach, container keeps running):
"%DOCKEREXE%" logs -f ninfer-coder390
