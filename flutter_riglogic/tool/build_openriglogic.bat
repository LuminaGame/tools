@echo off
rem Windows counterpart of build_openriglogic.sh: builds OpenRigLogic as a
rem static library with MSVC and the static CRT (/MT, matching the cl.exe
rem defaults the native-assets hook compiles flutter_riglogic.dll with), then
rem copies it to third_party\openriglogic\lib\riglogic.lib.
setlocal
set "DIR=%~dp0.."
set "OPENRIGLOGIC_DIR=%DIR%\third_party\openriglogic"
set "BUILD_DIR=%OPENRIGLOGIC_DIR%\build-windows"

if not defined VCINSTALLDIR (
  for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
)
if defined VSDIR call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

echo Building OpenRigLogic static library with MSVC (/MT)...
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
cmake -S "%OPENRIGLOGIC_DIR%" -B "%BUILD_DIR%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded ^
  -DBUILD_SHARED_LIBS=OFF ^
  -DRL_BUILD_TESTS=OFF ^
  -DRL_BUILD_EXAMPLES=OFF ^
  -DRL_BUILD_BENCHMARKS=OFF || exit /b 1
cmake --build "%BUILD_DIR%" || exit /b 1

if not exist "%OPENRIGLOGIC_DIR%\lib" mkdir "%OPENRIGLOGIC_DIR%\lib"
for %%f in ("%BUILD_DIR%\riglogic*.lib") do copy /y "%%f" "%OPENRIGLOGIC_DIR%\lib\riglogic.lib" >nul
echo OpenRigLogic static library built at %OPENRIGLOGIC_DIR%\lib\riglogic.lib
