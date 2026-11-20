# Build dx7render.exe (Windows, MSVC). Fetches Dexed's DX7 engine at a pinned commit into
# $Dest (outside the repo), adds small stand-ins for Dexed's plugin-only dependencies, and
# compiles dx7render.cpp against it.
#
#   powershell -ExecutionPolicy Bypass -File tools/open_samples_prep/dx7render/build.ps1 -Dest D:\tools\dx7render
#
# Licences: msfa is Apache-2.0; Dexed's EngineMkI is GPL-3.0. The binary is for local use;
# none of Dexed's code is stored in this repo.
param(
    [string]$Dest = "D:\tools\dx7render",
    [string]$Commit = "fea2f0f0f2c397799f59b27eb11c038cd34b22c5"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$raw = "https://raw.githubusercontent.com/asb2m10/dexed/$Commit/source"
$msfa = @("aligned_buf.h", "controllers.h", "dx7note.cc", "dx7note.h", "env.cc", "env.h", "exp2.cc",
          "exp2.h", "fm_core.cc", "fm_core.h", "fm_op_kernel.cc", "fm_op_kernel.h", "freqlut.cc",
          "freqlut.h", "lfo.cc", "lfo.h", "module.h", "pitchenv.cc", "pitchenv.h", "porta.cpp", "porta.h",
          "sin.cc", "sin.h", "synth.h", "tuning.h")
foreach ($d in @("msfa", "engine", "debugger", "stubs", "obj")) {
    New-Item -ItemType Directory -Force (Join-Path $Dest $d) | Out-Null
}
foreach ($f in $msfa) {
    $p = Join-Path $Dest "msfa\$f"
    if (-not (Test-Path $p)) { Invoke-WebRequest "$raw/msfa/$f" -OutFile $p -UseBasicParsing }
}
foreach ($f in @("EngineMkI.cpp", "EngineMkI.h")) {
    $p = Join-Path $Dest "engine\$f"
    if (-not (Test-Path $p)) { Invoke-WebRequest "$raw/engine/$f" -OutFile $p -UseBasicParsing }
}
Set-Content -Encoding ascii (Join-Path $Dest "COMMIT") $Commit

# Stand-ins: MTS-ESP microtuning client (never connected), the Surge tuning library type
# (only standard tuning is used), Dexed's logger, and standard tuning without JUCE.
Set-Content -Encoding ascii (Join-Path $Dest "stubs\libMTSClient.h") @"
#pragma once
typedef struct MTSClient MTSClient;
inline bool MTS_HasMaster(const MTSClient *) { return false; }
inline double MTS_NoteToFrequency(const MTSClient *, char, char) { return 440.0; }
"@
Set-Content -Encoding ascii (Join-Path $Dest "stubs\Tunings.h") @"
#pragma once
namespace Tunings { struct Tuning {}; }
"@
Set-Content -Encoding ascii (Join-Path $Dest "debugger\Logger.h") @"
#pragma once
#define TRACE(...) ((void)0)
"@
Set-Content -Encoding ascii (Join-Path $Dest "stubs\tuning_standard.cc") @"
#include "../msfa/tuning.h"
struct StandardTuning : public TuningState {
    StandardTuning() {
        const int base = 50857777;
        const int step = (1 << 24) / 12;
        for (int mn = 0; mn < 128; ++mn) table_[mn] = base + step * mn;
    }
    int32_t midinote_to_logfreq(int midinote) override { return table_[midinote]; }
    int table_[128];
};
std::shared_ptr<TuningState> createStandardTuning() { return std::make_shared<StandardTuning>(); }
void dexed_trace(const char *, const char *, ...) {}
"@

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "No MSVC (C++ build tools) found" }
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"
$srcs = @((Join-Path $here "dx7render.cpp"), (Join-Path $Dest "stubs\tuning_standard.cc"),
          (Join-Path $Dest "engine\EngineMkI.cpp")) + `
        ($msfa | Where-Object { $_ -match '\.(cc|cpp)$' } | ForEach-Object { Join-Path $Dest "msfa\$_" })
$src = ($srcs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$cmd = "`"$vcvars`" >nul && cl /nologo /O2 /EHsc /std:c++17 /MT /DNDEBUG /D_USE_MATH_DEFINES " +
       "/I`"$Dest`" /I`"$Dest\msfa`" /I`"$Dest\stubs`" /Fo`"$Dest\obj\\`" $src /Fe`"$Dest\dx7render.exe`""
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Write-Host "built $Dest\dx7render.exe"
