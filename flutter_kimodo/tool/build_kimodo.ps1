# Builds the kimodo.cpp prebuilt flutter_kimodo bundles (Windows x64).
#
#   powershell -ExecutionPolicy Bypass -File tool\build_kimodo.ps1 [-Vulkan auto|on|off] [-WorkDir <dir>] [-Clean]
#
# 1. checks out the pinned kimodo.cpp commit (tool\kimodo\UPSTREAM) and its
#    ggml submodule into <WorkDir>\src,
# 2. configures and builds it through tool\kimodo\CMakeLists.txt, which
#    compiles flutter_kimodo's C entry points (native\kimodo_lumina.cpp) into
#    the kimodo library, with CMake + Ninja under the Visual Studio 2022 x64
#    environment (dynamic CRT /MD, shared libraries) into <WorkDir>\out,
# 3. stages kimodo.dll, the ggml*.dll backends, kimodo.lib, the public headers,
#    the licences and a provenance file (lumina-kimodo.json),
# 4. packs <WorkDir>\dist\kimodo-<VERSION>-windows-x64.zip + .sha256 and
#    installs the same folder at <WorkDir>\prebuilt\<VERSION>\windows-x64, the
#    folder the native-assets hook reads by default.
#
# -Vulkan auto (default) builds the Vulkan backend when the Vulkan SDK is
# installed (VULKAN_SDK set, glslc present) and the CPU backend only
# otherwise. -Vulkan on fails without the SDK.
#
# Needs: Visual Studio 2022 with the C++ workload (its bundled CMake 3.25+ and
# Ninja are used when none is on PATH), git; for Vulkan the LunarG Vulkan SDK.
param(
  [ValidateSet('auto', 'on', 'off')] [string] $Vulkan = 'on',
  [string] $WorkDir = '',
  [switch] $Clean
)
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Log([string] $m) { Write-Host "[build_kimodo] $m" }
function Invoke-Native([string] $exe, [string[]] $argv) {
  & $exe @argv
  if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE): $($argv -join ' ')" }
}

$Package = Split-Path -Parent $PSScriptRoot
if (-not $WorkDir) { $WorkDir = if ($env:LUMINA_KIMODO_WORK) { $env:LUMINA_KIMODO_WORK } else { Join-Path $Package 'third_party\kimodo' } }
$Version = ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'kimodo\VERSION'))).Trim()
$Upstream = @{}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'kimodo\UPSTREAM'))) {
  if ($line -match '^\s*([a-z]+)=(.+)$') { $Upstream[$Matches[1]] = $Matches[2].Trim() }
}
$Name = "kimodo-$Version-windows-x64"
$Src = Join-Path $WorkDir 'src'
$Out = Join-Path $WorkDir 'out'
$Dist = Join-Path $WorkDir 'dist'
$Install = Join-Path $WorkDir "prebuilt\$Version\windows-x64"
Log "kimodo.cpp $($Upstream.commit) -> $Name"

# --- 1. Visual Studio 2022 x64 environment ---------------------------------
if (-not $env:VCINSTALLDIR) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path $vswhere)) { throw 'Visual Studio 2022 is not installed (vswhere.exe missing).' }
  $vs = & $vswhere -latest -version '[17.0,18.0)' -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $vs) { throw 'Visual Studio 2022 with the C++ workload was not found.' }
  $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
  Log "using $vs"
  foreach ($kv in (cmd /c "`"$vcvars`" >nul 2>nul && set")) {
    if ($kv -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
  }
}
foreach ($tool in 'cmake', 'ninja', 'cl', 'git') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH (Visual Studio 2022 C++ workload + git)." }
}
$cmakeVersion = ((cmake --version) | Select-Object -First 1) -replace 'cmake version ', ''
Log "cmake $cmakeVersion"

# --- 2. Vulkan SDK ----------------------------------------------------------
$glslc = $null
if (-not $env:VULKAN_SDK) {
  $sdkDir = Get-ChildItem -Path 'C:\VulkanSDK' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if ($sdkDir) {
    $env:VULKAN_SDK = $sdkDir.FullName
    Log "Discovered Vulkan SDK: $env:VULKAN_SDK"
  }
}
if ($env:VULKAN_SDK) {
  $candidate = Join-Path $env:VULKAN_SDK 'Bin\glslc.exe'
  if (Test-Path $candidate) { $glslc = $candidate }
}
if (-not $glslc) { $found = Get-Command glslc -ErrorAction SilentlyContinue; if ($found) { $glslc = $found.Source } }
$useVulkan = switch ($Vulkan) {
  'on' { if (-not $glslc) { throw 'Vulkan requested but the Vulkan SDK (VULKAN_SDK, glslc) is not installed: https://vulkan.lunarg.com/sdk/home' }; $true }
  'off' { $false }
  default { [bool] $glslc }
}
if ($useVulkan) { Log "Vulkan backend: on ($glslc)" } else { Log 'Vulkan backend: off (CPU only; install the Vulkan SDK for the GPU backend)' }

# --- 3. sources -------------------------------------------------------------
if ($Clean -and (Test-Path $Out)) { Remove-Item -Recurse -Force $Out }
if (-not (Test-Path (Join-Path $Src '.git'))) {
  New-Item -ItemType Directory -Force $Src | Out-Null
  Invoke-Native git @('-C', $Src, 'init', '-q')
  Invoke-Native git @('-C', $Src, 'remote', 'add', 'origin', $Upstream.repository)
}
$head = (git -C $Src rev-parse --verify -q HEAD)
if ($head -ne $Upstream.commit) {
  Log "fetching $($Upstream.commit)"
  Invoke-Native git @('-C', $Src, 'fetch', '-q', '--depth', '1', 'origin', $Upstream.commit)
  Invoke-Native git @('-C', $Src, 'checkout', '-q', '--force', $Upstream.commit)
}
Invoke-Native git @('-C', $Src, 'submodule', 'update', '--init', '--depth', '1', '-q')
$ggmlCommit = (git -C (Join-Path $Src 'ggml') rev-parse HEAD).Trim()
Log "ggml $ggmlCommit"

# --- 4. configure + build ---------------------------------------------------
$vk = if ($useVulkan) { 'ON' } else { 'OFF' }
# tool\kimodo\CMakeLists.txt wraps the checkout and compiles native\kimodo_lumina.cpp
# (multi-prompt sequences, backend selection) into kimodo.dll.
$cfg = @('-S', (Join-Path $PSScriptRoot 'kimodo'), '-B', $Out, '-G', 'Ninja',
  "-DKIMODO_SOURCE_DIR=$($Src.Replace('\', '/'))",
  '-DCMAKE_BUILD_TYPE=Release',
  '-DBUILD_SHARED_LIBS=ON',
  '-DBUILD_TESTING=OFF',
  '-DKIMODO_BUILD_TESTS=OFF',
  "-DKIMODO_ENABLE_VULKAN=$vk",
  '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL',
  '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW')
if ($useVulkan) { $cfg += "-DVulkan_GLSLC_EXECUTABLE=$glslc" }
Invoke-Native cmake $cfg
Invoke-Native cmake @('--build', $Out, '--target', 'kimodo', 'kmd-generate', 'kmd-inspect')

# --- 5. stage ---------------------------------------------------------------
$Stage = Join-Path $Dist "stage\$Name"
if (Test-Path (Join-Path $Dist 'stage')) { Remove-Item -Recurse -Force (Join-Path $Dist 'stage') }
foreach ($d in 'bin', 'lib', 'include\kimodo', 'licenses') { New-Item -ItemType Directory -Force (Join-Path $Stage $d) | Out-Null }
$dlls = @(Get-ChildItem -Path $Out -Recurse -Filter '*.dll' | Where-Object { $_.Name -match '^(kimodo|ggml[\w-]*)\.dll$' })
if (-not ($dlls | Where-Object Name -eq 'kimodo.dll')) { throw 'kimodo.dll was not built' }
foreach ($f in $dlls) { Copy-Item $f.FullName (Join-Path $Stage 'bin') -Force }
foreach ($exe in 'kmd-generate.exe', 'kmd-inspect.exe') {
  $f = Get-ChildItem -Path $Out -Recurse -Filter $exe | Select-Object -First 1
  if ($f) { Copy-Item $f.FullName (Join-Path $Stage 'bin') -Force }
}
$importLib = Get-ChildItem -Path $Out -Recurse -Filter 'kimodo.lib' | Select-Object -First 1
if (-not $importLib) { throw 'kimodo.lib (import library) was not built' }
Copy-Item $importLib.FullName (Join-Path $Stage 'lib') -Force
Copy-Item (Join-Path $Src 'include\kimodo\*') (Join-Path $Stage 'include\kimodo') -Force
Copy-Item (Join-Path $Package 'native\kimodo_lumina.h') (Join-Path $Stage 'include') -Force
Copy-Item (Join-Path $Src 'LICENSE') (Join-Path $Stage 'licenses\kimodo.cpp-LICENSE.txt')
Copy-Item (Join-Path $Src 'NOTICE') (Join-Path $Stage 'licenses\kimodo.cpp-NOTICE.txt')
Copy-Item (Join-Path $Src 'ggml\LICENSE') (Join-Path $Stage 'licenses\ggml-LICENSE.txt')
$cache = [IO.File]::ReadAllText((Join-Path $Out 'CMakeCache.txt'))
$compiler = if ($cache -match 'CMAKE_CXX_COMPILER:[A-Z]+=(.+)') { $Matches[1].Trim() } else { 'unknown' }
$meta = [ordered]@{
  version = $Version
  platform = 'windows-x64'
  upstream = [ordered]@{ repository = $Upstream.repository; commit = $Upstream.commit; ggml = $ggmlCommit }
  backends = @('cpu') + $(if ($useVulkan) { @('vulkan') } else { @() })
  build = [ordered]@{ cmake = $cfg[5..($cfg.Length - 1)]; cmake_version = $cmakeVersion; compiler = $compiler; crt = '/MD (dynamic)' }
  dlls = @($dlls | ForEach-Object Name | Sort-Object)
}
[IO.File]::WriteAllText((Join-Path $Stage 'lumina-kimodo.json'), ($meta | ConvertTo-Json -Depth 6) + "`n", $Utf8)

# --- 6. archive + checksum + install -----------------------------------------
$Archive = Join-Path $Dist "$Name.zip"
if (Test-Path $Archive) { Remove-Item -Force $Archive }
Push-Location (Join-Path $Dist 'stage')
try { Invoke-Native "$env:SystemRoot\System32\tar.exe" @('-a', '-c', '-f', $Archive, $Name) } finally { Pop-Location }
$hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$Archive.sha256", "$hash  $Name.zip`n", $Utf8)
if (Test-Path $Install) { Remove-Item -Recurse -Force $Install }
New-Item -ItemType Directory -Force (Split-Path -Parent $Install) | Out-Null
Move-Item $Stage $Install
Remove-Item -Recurse -Force (Join-Path $Dist 'stage')
$size = (Get-Item $Archive).Length / 1MB
Log ("{0} ({1:N1} MiB) sha256 {2}" -f $Archive, $size, $hash)
Log "installed at $Install"
