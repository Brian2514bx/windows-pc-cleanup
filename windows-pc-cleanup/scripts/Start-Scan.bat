@echo off
cd /d "%~dp0"
echo Scanning your PC (read-only, nothing will be changed). This can take a few minutes...
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scan.ps1" -PickFolder -OutDir "%USERPROFILE%\Desktop\pc-scan"
copy /y "%~dp0recycle.ps1" "%USERPROFILE%\Desktop\pc-scan\recycle.ps1" >nul
copy /y "%~dp0run_cleanup.bat" "%USERPROFILE%\Desktop\pc-scan\run_cleanup.bat" >nul
echo.
echo Finished. The report has opened in your browser.
pause
