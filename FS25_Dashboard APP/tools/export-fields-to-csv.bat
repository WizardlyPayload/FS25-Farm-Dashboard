@echo off
cd /d "%~dp0.."
node tools\export-fields-to-csv.mjs
if errorlevel 1 exit /b 1
echo.
echo Open fields-from-savegame.csv in Excel (same folder as this app).
pause
