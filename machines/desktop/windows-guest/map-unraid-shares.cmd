@echo off
rem Map the Unraid photo shares (Node804, 10.0.1.10) as drive letters.
rem Run once inside Windows, from a normal (not admin) Command Prompt or by
rem double-clicking: mapped drives belong to the user who maps them, and an
rem elevated window would map them where Explorer can't see them.
rem
rem Both drives use one saved Unraid login. Windows allows only one set of
rem credentials per server, and Windows 11 refuses guest access by default,
rem so "photos" goes through the same login as "private".
rem The password prompt comes from cmdkey; it is stored in Windows
rem Credential Manager, not in this file.

set SERVER=10.0.1.10
set /p UNRAID_USER=Unraid user name: 
cmdkey /add:%SERVER% /user:%UNRAID_USER% /pass
if errorlevel 1 goto :fail

net use P: \\%SERVER%\photos /persistent:yes
if errorlevel 1 goto :fail
net use R: \\%SERVER%\private /persistent:yes
if errorlevel 1 goto :fail

echo.
echo Mapped P: = photos, R: = private. They reconnect at every sign-in.
pause
exit /b 0

:fail
echo.
echo Mapping failed. To start over: net use P: /delete ^& net use R: /delete ^& cmdkey /delete:%SERVER%
pause
exit /b 1
