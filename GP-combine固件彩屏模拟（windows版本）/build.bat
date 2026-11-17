@echo off
setlocal enabledelayedexpansion
set "PATH=%WINDIR%\System32;%WINDIR%;%PATH%"
chcp 65001 >nul

REM ---- locate sim dir and repo root ----
set "SIM=%~dp0"
if "%SIM:~-1%"=="\" set "SIM=%SIM:~0,-1%"
if exist "%SIM%\..\esp32" (set "REPO=%SIM%\..") else (set "REPO=%SIM%\..\..")

set "FQBN=esp32:esp32:esp32s3:PSRAM=opi,FlashSize=16M,PartitionScheme=custom"

set "ARG=%~1"
if "%ARG%"=="" set "ARG=240"
set "DEF_SKETCH="
if /i "%ARG%"=="240" set "DEF_SKETCH=%REPO%\esp32"
if /i "%ARG%"=="320" set "DEF_SKETCH=%REPO%\esp32_170x320"
if /i "%ARG%"=="172" set "DEF_SKETCH=%REPO%\esp32_172x320"
if /i "%ARG%"=="-h" goto :usage
if /i "%ARG%"=="--help" goto :usage
if "%DEF_SKETCH%"=="" set "DEF_SKETCH=%ARG%"
if not "%SKETCH%"=="" set "DEF_SKETCH=%SKETCH%"
set "SKETCH=%DEF_SKETCH%"

for %%F in ("%SKETCH%") do set "NAME=%%~nxF"
REM 共享库/headless 短名：170/172 都是 320 宽但各编各的库，按工程名区分（与 Linux build.sh 一致）
set "TAG=240"
if /i "%NAME%"=="esp32_172x320" set "TAG=172"
if /i "%NAME%"=="esp32_170x320" set "TAG=320"
set "BUILD=%SIM%\build\%NAME%"
set "GEN=%SIM%\build\gen"
set "SRC=%BUILD%\sketch\%NAME%.ino.cpp"

if not exist "%SKETCH%" (
  echo [build] sketch dir not found: %SKETCH%
  exit /b 1
)

if not exist "%BUILD%" mkdir "%BUILD%"

REM 1) generate the prototype-filled .ino.cpp via arduino-cli if missing
if not exist "%SRC%" (
  echo [build] first run: calling arduino-cli to generate .ino.cpp ^(a few minutes, once only^)
  set "CLI=arduino-cli"
  where arduino-cli >nul 2>&1 || set "CLI=C:\Program Files\Arduino CLI\arduino-cli.exe"
  "!CLI!" compile --fqbn "%FQBN%" --build-path "%BUILD%" "%SKETCH%" || (echo [build] arduino-cli compile failed & exit /b 1)
)

if not exist "%GEN%" mkdir "%GEN%"
copy /Y "%SRC%" "%GEN%\esp32.ino.cpp" >nul || (echo [build] copy ino.cpp failed & exit /b 1)

REM 1b) read firmware SCR_W/SCR_H from generated source (fall back 240x135)
set "SIM_W=240"
set "SIM_H=135"
for /f "tokens=3" %%a in ('findstr /C:"#define SCR_W" "%SRC%"') do set "SIM_W=%%a"
for /f "tokens=3" %%a in ('findstr /C:"#define SCR_H" "%SRC%"') do set "SIM_H=%%a"

REM 2) collect extra cpp under sketch/src (embedded NES emulator)
set "EXTRA="
if exist "%SKETCH%\src" (
  for /f "delims=" %%F in ('dir /s /b "%SKETCH%\src\*.cpp"') do set "EXTRA=!EXTRA! "%%F""
)

REM 3) locate MSVC toolchain via vswhere
set "VCVAR="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
  for /f "usebackq delims=" %%D in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%D"
  if defined VSPATH set "VCVAR=%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat"
)
if not exist "%VCVAR%" set "VCVAR=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VCVAR%" set "VCVAR=C:\Program Files\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VCVAR%" (echo [build] MSVC vcvarsall.bat not found & exit /b 1)
call "%VCVAR%" x64

REM 4) attach Windows SDK include/lib (vcvarsall may not register the SDK automatically)
set "SDKROOT=C:\Program Files (x86)\Windows Kits\10"
set "SDKVER="
for /f "delims=" %%D in ('dir /b /ad "%SDKROOT%\Include"') do set "SDKVER=%%D"
set "INCLUDE=%SDKROOT%\Include\%SDKVER%\ucrt;%SDKROOT%\Include\%SDKVER%\um;%SDKROOT%\Include\%SDKVER%\shared;%SDKROOT%\Include\%SDKVER%\cppwinrt;%INCLUDE%"
set "LIB=%SDKROOT%\Lib\%SDKVER%\ucrt\x64;%SDKROOT%\Lib\%SDKVER%\um\x64;%LIB%"

echo [build] %NAME%  (sketch %SKETCH%)
if not exist "%BUILD%" mkdir "%BUILD%"

REM 构建形态：SIM_SHARED=1 -> 共享库 libsim<TAG>.dll（配置助手内嵌预览）；默认 -> 独立 exe
if /i "%SIM_SHARED%"=="1" (
  set "OUT=%SIM%\build\libsim%TAG%.dll"
  set "LIBFLAGS=/LD /DSIM_LIB"
  echo [build] 共享库构建（配置助手内嵌预览）
) else (
  set "OUT=%SIM%\build\sim_%NAME%.exe"
  set "LIBFLAGS="
)

cl /nologo /std:c++17 /O2 /w /EHsc /utf-8 !LIBFLAGS! ^
  /DSIM_IMG_W=%SIM_W% /DSIM_IMG_H=%SIM_H% ^
  /I "%SIM%\shim" /I "%SKETCH%" /I "%GEN%" ^
  /Fo"%BUILD%\\" /Fe"!OUT!" ^
  "%SIM%\sim_main.cpp" %EXTRA% ^
  user32.lib gdi32.lib gdiplus.lib || (echo [build] cl failed & exit /b 1)

if /i not "%SIM_SHARED%"=="1" goto :exe_done

REM 共享库产物拷到配置助手 bin 目录
if not exist "%REPO%\pc_app\gpfusion_wizard\bin" mkdir "%REPO%\pc_app\gpfusion_wizard\bin"
copy /Y "!OUT!" "%REPO%\pc_app\gpfusion_wizard\bin\libsim%TAG%.dll" >nul
if errorlevel 1 (echo [build] copy dll to wizard bin failed & exit /b 1)
echo [build] OK -^> build\libsim%TAG%.dll  (copied to gpfusion_wizard\bin)
goto :build_done

:exe_done
echo [build] OK -^> build\sim_%NAME%.exe
echo [build] run: run.bat %ARG% --mode=keys --scale=3

:build_done
exit /b 0

:usage
echo Usage: build.bat [240^|320^|172^|sketch-dir]
exit /b 0
