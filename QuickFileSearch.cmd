@echo off
rem Double-click launcher. Runs the search tool without a console window or execution-policy prompts.
start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0QuickFileSearch.ps1"
