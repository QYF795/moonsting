# Install the MSVC toolchain that `moon` needs for `--target native` on Windows.
#
#   powershell -ExecutionPolicy Bypass -File script/install-msvc.ps1
#
# Why: the native backend links through cl.exe / clang-cl.exe plus the Windows
# SDK. Without it `moon build --target native` fails with
#   "Windows native backend requires MSVC Build Tools with C++ tools and Windows SDK".
#
# The installer is ~4-6 GB and needs an elevated shell (UAC). Nothing in this
# repository requires native: wasm-gc and js work on a bare toolchain. Native is
# what unlocks the process-isolated worker (crash recovery, `--jobs`).

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent(
)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "需要管理员权限：请在“以管理员身份运行”的 PowerShell 里重跑本脚本。" -ForegroundColor Yellow
  Write-Host "  powershell -ExecutionPolicy Bypass -File script/install-msvc.ps1"
  exit 1
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "未找到 winget（应用安装程序）。请从 Microsoft Store 安装 'App Installer' 后重试。" -ForegroundColor Red
  exit 1
}

Write-Host "安装 Visual Studio 2022 Build Tools + VCTools 工作负载（约 4-6 GB，10-40 分钟）..."
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact `
  --accept-package-agreements --accept-source-agreements `
  --override "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

if ($LASTEXITCODE -ne 0) {
  Write-Host "winget 返回 $LASTEXITCODE。可改用手动安装：https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor Yellow
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "验证："
Write-Host "  moon build --target native"
Write-Host "  moon run cli --target native -- run --target varint --seed 1"
Write-Host ""
Write-Host "如果 moon 仍找不到编译器，请从“x64 Native Tools Command Prompt for VS 2022”里运行，"
Write-Host "或把 VS 的 vcvars64.bat 先 source 进当前会话。"
