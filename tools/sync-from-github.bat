@echo off
REM Matches local app + mod sources to: https://github.com/WizardlyPayload/FS25-Farm-Dashboard/tree/main
cd /d "%~dp0\.."
node tools\sync-upstream-wizardlypayload.mjs
echo.
if errorlevel 1 (echo Sync had errors.) else (echo Done.)
pause
