@echo off
rem Builds OpenRigLogic as a static library for Android (arm64-v8a, x86_64) using the Android NDK and CMake.
rem Libraries are copied to third_party\openriglogic\lib\android\<abi>\libriglogic.a.
setlocal enabledelayedexpansion

set "DIR=%~dp0.."
set "OPENRIGLOGIC_DIR=%DIR%\third_party\openriglogic"

rem 1. Locate Android NDK
if defined ANDROID_NDK_HOME (
  set "NDK_DIR=%ANDROID_NDK_HOME%"
) else if defined ANDROID_NDK (
  set "NDK_DIR=%ANDROID_NDK%"
) else if exist "%LOCALAPPDATA%\Android\Sdk\ndk" (
  for /f "delims=" %%d in ('dir /b /ad /o-n "%LOCALAPPDATA%\Android\Sdk\ndk"') do (
    if not defined NDK_DIR set "NDK_DIR=%LOCALAPPDATA%\Android\Sdk\ndk\%%d"
  )
)

if not defined NDK_DIR (
  echo Error: Android NDK not found. Set ANDROID_NDK_HOME or install NDK via Android Studio.
  exit /b 1
)
echo Using Android NDK: %NDK_DIR%

rem 2. Locate CMake and Ninja
if not defined CMAKE_EXE (
  if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
    set "CMAKE_EXE=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    set "NINJA_EXE=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
  ) else (
    set "CMAKE_EXE=cmake"
    set "NINJA_EXE=ninja"
  )
)

set "TARGET_ABIS=arm64-v8a x86_64 armeabi-v7a"
if not "%~1"=="" set "TARGET_ABIS=%~1"

for %%A in (%TARGET_ABIS%) do (
  echo ========================================================
  echo Building OpenRigLogic for Android ABI: %%A
  echo ========================================================
  set "BUILD_DIR=%OPENRIGLOGIC_DIR%\build-android-%%A"
  set "OUT_DIR=%OPENRIGLOGIC_DIR%\lib\android\%%A"

  if not exist "!OUT_DIR!" mkdir "!OUT_DIR!"

  "%CMAKE_EXE%" -S "%OPENRIGLOGIC_DIR%" -B "!BUILD_DIR!" -G Ninja ^
    -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" ^
    -DCMAKE_TOOLCHAIN_FILE="%NDK_DIR%\build\cmake\android.toolchain.cmake" ^
    -DANDROID_ABI=%%A ^
    -DANDROID_PLATFORM=android-26 ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DANDROID_STL=c++_shared ^
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON ^
    -DCMAKE_CXX_FLAGS="-fPIC" ^
    -DCMAKE_C_FLAGS="-fPIC" ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DRL_BUILD_TESTS=OFF ^
    -DRL_BUILD_EXAMPLES=OFF ^
    -DRL_BUILD_BENCHMARKS=OFF || exit /b 1

  "%CMAKE_EXE%" --build "!BUILD_DIR!" || exit /b 1

  for %%f in ("!BUILD_DIR!\libriglogic*.a") do (
    copy /y "%%f" "!OUT_DIR!\libriglogic.a" >nul
    echo Copied %%f to !OUT_DIR!\libriglogic.a
  )
)

echo.
echo All requested Android OpenRigLogic libraries successfully built!
