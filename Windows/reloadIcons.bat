@echo off
REM ---------------------------------------------------------
REM This script clears and rebuilds the Windows icon cache.
REM ---------------------------------------------------------

REM 1. Terminate Windows Explorer (forcefully) so the icon cache file is not in use
taskkill /f /im explorer.exe

REM 2. Switch to the Local AppData folder for the current user
cd /d %userprofile%\AppData\Local

REM 3. Delete the IconCache.db file (removes all cached icons)
del IconCache.db /a

REM 4. Restart Windows Explorer to regenerate the icon cache
start explorer.exe
