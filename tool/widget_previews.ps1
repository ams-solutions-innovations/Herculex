#!/usr/bin/env pwsh
# Regenerates the home-screen widget picker previews,
# android/app/src/main/res/drawable-nodpi/widget_preview_*.png, from the real
# renderers (android/app/src/test/kotlin/com/ams/herculex/WidgetPreviews.kt).
#
# The renderers need a real Android graphics stack and the system fonts, which
# only a proper app process has. So this packs them into a throwaway APK
# (com.ams.hxprev), installs it on a running EMULATOR, runs it, pulls the PNGs
# and uninstalls it. A physical device is refused on purpose.
#
# Usage:
#   tool\widget_previews.ps1                          # the one running emulator
#   tool\widget_previews.ps1 -Serial emulator-5554
#   tool\widget_previews.ps1 -Looks .\looks   # glass contact sheets only
#
# -Looks renders contact sheets (every transparency level, squircle and pill,
# over a busy backdrop, dark and light) into the given folder, for judging the
# glass by eye. It leaves the real previews alone.
#
# Run after changing a widget renderer (HxWidgetRenderers.kt,
# HxTrainingRenderers.kt, HxWidgetKit.kt) or the demo data in WidgetPreviews.kt.

param([string]$Serial, [string]$Looks)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$android = Join-Path $repoRoot 'android'
$package = 'com.ams.hxprev'

# Windows PowerShell 5.1 turns anything a native tool writes to stderr (Gradle's
# warnings, adb's progress) into a terminating error or red noise. This keeps it
# as plain text; exit codes are checked by hand.
function Native([scriptblock]$Command) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Command 2>&1 | ForEach-Object {
            if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        }
    } finally { $ErrorActionPreference = $saved }
}

# ── Tools ────────────────────────────────────────────────────────────────
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) {
    $line = Get-Content (Join-Path $android 'local.properties') | Where-Object { $_ -like 'sdk.dir=*' }
    $sdk = ($line -replace '^sdk\.dir=', '') -replace '\\\\', '\' -replace '\\:', ':'
}
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$bt = (Get-ChildItem (Join-Path $sdk 'build-tools') | Sort-Object { [version]($_.Name -replace '-.*') } | Select-Object -Last 1).FullName
$platform = Get-ChildItem (Join-Path $sdk 'platforms') -Filter 'android-*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'android.jar') } |
    Sort-Object { [double](($_.Name -replace '^android-') -replace '[^0-9.].*') } | Select-Object -Last 1
$androidJar = Join-Path $platform.FullName 'android.jar'
$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $keystore)) { throw "No debug keystore at $keystore (build a debug APK once to create it)." }

# ── Target: an emulator, never a phone ───────────────────────────────────
if (-not $Serial) {
    $emulators = @(Native { & $adb devices } | Select-String '^(emulator-\d+)\s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if ($emulators.Count -ne 1) {
        throw "Expected exactly one running emulator, found $($emulators.Count). Start one or pass -Serial."
    }
    $Serial = $emulators[0]
}
if ($Serial -notlike 'emulator-*') {
    throw "Refusing to run on '$Serial': this only targets emulators."
}

# ── Compile the renderers (main + test source sets) ──────────────────────
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr' }
Push-Location $android
try {
    # Only Kotlin is needed; skipping the Dart build keeps a half-edited lib/ from blocking this.
    Native { & .\gradlew.bat ':app:compileDebugUnitTestKotlin' -x compileFlutterBuildDebug --console=plain }
    if ($LASTEXITCODE -ne 0) { throw 'Gradle compile failed.' }
} finally {
    Pop-Location
}

# ── Build the throwaway APK ──────────────────────────────────────────────
$classes = @(
    # The Hx* files, plus SvgPath, which HxWidgetKit.kt declares under another name.
    Get-ChildItem (Join-Path $repoRoot 'build\app\tmp\kotlin-classes\debug\com\ams\herculex') -Include 'Hx*.class', 'SvgPath*.class' -Recurse
    Get-ChildItem (Join-Path $repoRoot 'build\app\tmp\kotlin-classes\debugUnitTest\com\ams\herculex') -Include 'WidgetPreviews*.class', 'PreviewRunner*.class' -Recurse
) | ForEach-Object { $_.FullName }

$stdlib = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1\org.jetbrains.kotlin\kotlin-stdlib') -Directory |
    Where-Object { $_.Name -match '^2\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } | Select-Object -Last 1 |
    ForEach-Object { Get-ChildItem $_.FullName -Recurse -Filter "kotlin-stdlib-$($_.Name).jar" } | Select-Object -First 1
if (-not $stdlib) { throw 'No kotlin-stdlib 2.x jar in the Gradle cache.' }

$work = Join-Path ([IO.Path]::GetTempPath()) 'hxprev'
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path "$work\dex", "$work\assets", "$work\out" | Out-Null
# Straight in assets/ (not assets/fonts/): aapt2 on Windows writes nested entries
# with a backslash, which AssetManager then can't find.
Copy-Item (Join-Path $repoRoot 'assets\fonts\*.ttf') "$work\assets"

Native { & (Join-Path $bt 'd8.bat') --lib $androidJar --min-api 26 --output "$work\dex" @classes $stdlib.FullName }
if ($LASTEXITCODE -ne 0) { throw 'd8 failed.' }

@"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$package">
    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="34" />
    <application android:label="hxprev" android:debuggable="true">
        <activity android:name="com.ams.herculex.PreviewRunner" android:exported="true"
            android:theme="@android:style/Theme.NoDisplay" />
    </application>
</manifest>
"@ | Set-Content -Path "$work\AndroidManifest.xml" -Encoding UTF8

Native { & (Join-Path $bt 'aapt2.exe') link -o "$work\base.apk" -I $androidJar --manifest "$work\AndroidManifest.xml" -A "$work\assets" }
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open("$work\base.apk", 'Update')
try {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$work\dex\classes.dex", 'classes.dex')
} finally {
    $zip.Dispose()
}
Native { & (Join-Path $bt 'zipalign.exe') -f -p 4 "$work\base.apk" "$work\aligned.apk" }
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed.' }
Native { & (Join-Path $bt 'apksigner.bat') sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out "$work\hxprev.apk" "$work\aligned.apk" }
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed.' }

# ── Run it on the emulator, pull the PNGs ────────────────────────────────
$remote = "/sdcard/Android/data/$package/files/out"
try {
    Native { & $adb -s $Serial install -r "$work\hxprev.apk" } | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'adb install failed.' }
    $extras = if ($Looks) { @('--ez', 'looks', 'true') } else { @() }
    Native { & $adb -s $Serial shell am start -W -n "$package/com.ams.herculex.PreviewRunner" @extras } | Out-Null

    $state = $null
    for ($i = 0; $i -lt 60 -and -not $state; $i++) {
        $ls = (Native { & $adb -s $Serial shell "ls $remote 2>/dev/null" }) -join ' '
        if ($ls -match '\bFAILED\b') { $state = 'FAILED' } elseif ($ls -match '\bDONE\b') { $state = 'DONE' } else { Start-Sleep -Seconds 1 }
    }
    if ($state -ne 'DONE') {
        if ($state -eq 'FAILED') { Native { & $adb -s $Serial shell "cat $remote/FAILED" } | ForEach-Object { Write-Host $_ } }
        throw "The renderer did not finish ($state)."
    }
    Native { & $adb -s $Serial pull "$remote/." "$work\out" } | Out-Null
} finally {
    Native { & $adb -s $Serial uninstall $package } | Out-Null
}

if ($Looks) {
    New-Item -ItemType Directory -Path $Looks -Force | Out-Null
    Get-ChildItem "$work\out" -Filter 'looks_*.png' | Copy-Item -Destination $Looks -Force
    Write-Host "Wrote contact sheets to $Looks"
    return
}

# ── Install, with a sanity check ─────────────────────────────────────────
$dest = Join-Path $android 'app\src\main\res\drawable-nodpi'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$expected = @(Get-ChildItem (Join-Path $android 'app\src\main\res\xml') -Filter 'widget_info_*.xml').Count
$pngs = @(Get-ChildItem "$work\out" -Filter 'widget_preview_*.png')
if ($pngs.Count -ne $expected) { throw "Rendered $($pngs.Count) previews, expected $expected." }
$tiny = $pngs | Where-Object { $_.Length -lt 2048 }
if ($tiny) { throw "Suspiciously small previews: $($tiny.Name -join ', ')" }
$pngs | Copy-Item -Destination $dest -Force
Write-Host "Updated $($pngs.Count) previews in $dest"
