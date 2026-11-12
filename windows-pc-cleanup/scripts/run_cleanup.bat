@echo off
cd /d "%~dp0"
echo === STEP 1: DRY RUN (nothing is moved yet) ===
powershell -NoProfile -ExecutionPolicy Bypass -File .\recycle.ps1 -ListFile .\approved.txt
echo.
echo Close Chrome, Edge, Discord, Steam and games first.
echo Press any key to MOVE these to the Recycle Bin, or close this window to cancel.
pause >nul
powershell -NoProfile -ExecutionPolicy Bypass -File .\recycle.ps1 -ListFile .\approved.txt -Execute -LogFile .\cleanup-log.txt
echo.
echo Done. Log saved to cleanup-log.txt
pause
