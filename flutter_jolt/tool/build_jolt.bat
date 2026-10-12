@echo off
rem Fetches the pinned Jolt Physics release (tool\jolt_version.txt) into
rem third_party\jolt\src and builds it as a static library with MSVC and the
rem static CRT (/MT, matching the cl.exe defaults the native-assets hook
rem compiles flutter_jolt.dll with). The result is a self-contained folder the
rem hook reads (the `jolt_dir` user-define, default third_party\jolt):
rem   third_party\jolt\include\Jolt\...   the headers
rem   third_party\jolt\lib\Jolt.lib       the static library
rem   third_party\jolt\jolt_defines.txt   the JPH_* defines Jolt was built with
rem   third_party\jolt\VERSION            the tag and commit
rem Usage: tool\build_jolt.bat [--clean]
setlocal EnableDelayedExpansion
set "DIR=%~dp0.."
set "JOLT_DIR=%DIR%\third_party\jolt"
set "SRC_DIR=%JOLT_DIR%\src"
set "BUILD_DIR=%JOLT_DIR%\build-windows"

for /f "usebackq tokens=1,2" %%a in ("%DIR%\tool\jolt_version.txt") do (
  if "%%a"=="tag" set "JOLT_TAG=%%b"
  if "%%a"=="commit" set "JOLT_COMMIT=%%b"
)
if not defined JOLT_TAG (echo tool\jolt_version.txt names no tag & exit /b 1)

if "%~1"=="--clean" if exist "%JOLT_DIR%" rmdir /s /q "%JOLT_DIR%"

if not defined VCINSTALLDIR (
  for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
)
if defined VSDIR call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

if not exist "%SRC_DIR%\Jolt\Jolt.h" (
  echo Fetching Jolt Physics %JOLT_TAG%...
  git clone --depth 1 --branch %JOLT_TAG% https://github.com/jrouwe/JoltPhysics.git "%SRC_DIR%" || exit /b 1
)
for /f "usebackq delims=" %%c in (`git -C "%SRC_DIR%" rev-parse HEAD`) do set "HEAD_COMMIT=%%c"
if /i not "%HEAD_COMMIT%"=="%JOLT_COMMIT%" (
  echo Jolt checkout is at %HEAD_COMMIT%, expected %JOLT_COMMIT% ^(%JOLT_TAG%^). Run with --clean.
  exit /b 1
)

echo Building Jolt Physics %JOLT_TAG% static library with MSVC (/MT)...
cmake -S "%SRC_DIR%\Build" -B "%BUILD_DIR%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ^
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW ^
  -DUSE_STATIC_MSVC_RUNTIME_LIBRARY=ON ^
  -DINTERPROCEDURAL_OPTIMIZATION=OFF ^
  -DGENERATE_DEBUG_SYMBOLS=OFF ^
  -DDOUBLE_PRECISION=OFF ^
  -DCROSS_PLATFORM_DETERMINISTIC=OFF ^
  -DOBJECT_LAYER_BITS=16 ^
  -DCPP_EXCEPTIONS_ENABLED=ON ^
  -DCPP_RTTI_ENABLED=ON ^
  -DDEBUG_RENDERER_IN_DEBUG_AND_RELEASE=OFF ^
  -DPROFILER_IN_DEBUG_AND_RELEASE=OFF ^
  -DFLOATING_POINT_EXCEPTIONS_ENABLED=OFF ^
  -DENABLE_ALL_WARNINGS=OFF ^
  -DOVERRIDE_CXX_FLAGS=OFF ^
  -DUSE_SSE4_1=ON -DUSE_SSE4_2=ON ^
  -DUSE_AVX=OFF -DUSE_AVX2=OFF -DUSE_AVX512=OFF ^
  -DUSE_LZCNT=OFF -DUSE_TZCNT=OFF -DUSE_F16C=OFF -DUSE_FMADD=OFF ^
  -DCMAKE_VS_PLATFORM_NAME=x64 ^
  -DJPH_USE_DX12=OFF -DJPH_USE_VK=OFF -DJPH_USE_MTL=OFF -DJPH_USE_CPU_COMPUTE=OFF ^
  -DENABLE_OBJECT_STREAM=OFF -DENABLE_INSTALL=OFF ^
  -DTARGET_UNIT_TESTS=OFF -DTARGET_HELLO_WORLD=OFF -DTARGET_PERFORMANCE_TEST=OFF ^
  -DTARGET_SAMPLES=OFF -DTARGET_VIEWER=OFF || exit /b 1
cmake --build "%BUILD_DIR%" --target Jolt || exit /b 1

if not exist "%JOLT_DIR%\lib" mkdir "%JOLT_DIR%\lib"
copy /y "%BUILD_DIR%\Jolt.lib" "%JOLT_DIR%\lib\Jolt.lib" >nul || exit /b 1
if exist "%JOLT_DIR%\include" rmdir /s /q "%JOLT_DIR%\include"
robocopy "%SRC_DIR%\Jolt" "%JOLT_DIR%\include\Jolt" *.h *.inl /S /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 exit /b 1
call dart "%DIR%\tool\write_jolt_defines.dart" "%BUILD_DIR%\compile_commands.json" "%JOLT_DIR%\jolt_defines.txt" || exit /b 1
(echo tag %JOLT_TAG%& echo commit %JOLT_COMMIT%) > "%JOLT_DIR%\VERSION"
echo Jolt Physics %JOLT_TAG% built at %JOLT_DIR%
exit /b 0
