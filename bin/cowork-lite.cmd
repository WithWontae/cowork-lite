@echo off
rem Wrapper so PowerShell and cmd can run cowork-lite. The real work is done by bin\cowork-lite in Git Bash.
rem Keep everything before "chcp 65001" ASCII-only: this file is UTF-8 and cmd reads it in the console code page.
setlocal
for /f "tokens=2 delims=:" %%a in ('chcp') do set "CL_OLDCP=%%a"
chcp 65001 >nul

set "CL_BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "CL_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined CL_BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "CL_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined CL_BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "CL_BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if defined COWORK_LITE_BASH set "CL_BASH=%COWORK_LITE_BASH%"
if not defined CL_BASH (
  echo Git Bash를 찾을 수 없습니다. 한 줄 설치 명령을 다시 실행해 주세요.
  chcp %CL_OLDCP% >nul
  exit /b 1
)

rem Tells "cowork-lite uninstall" that this wrapper is running, so it must not delete the wrapper itself.
set "COWORK_LITE_VIA_CMD=1"
"%CL_BASH%" "%~dp0cowork-lite" %*
set "CL_RC=%errorlevel%"
chcp %CL_OLDCP% >nul

rem After uninstall, bash leaves uninstalled.flag. Delete this wrapper and its folder now. The (goto) trick drops the
rem batch context first, so deleting the running file does not print "The batch file cannot be found."
if exist "%~dp0uninstalled.flag" (goto) 2>nul & del "%~dp0uninstalled.flag" & del "%~f0" & rmdir "%~dp0" 2>nul
exit /b %CL_RC%
