# xunit-run v1.0 — Run xUnit tests for 1C via vanessa-runner
# Source: https://github.com/PraimSXoce/cc-1c-skills
<#
.SYNOPSIS
    Запуск xUnit-тестов 1С через vanessa-runner (vrunner)

.DESCRIPTION
    Находит vrunner, генерирует/использует env.json, запускает тесты,
    парсит JUnit XML и выводит сводку результатов.

.PARAMETER TestPath
    Папка с EPF-тестами или конкретный EPF-файл (по умолчанию "tests")

.PARAMETER V8Version
    Версия платформы 1С (например, "8.3.27.1859")

.PARAMETER InfoBasePath
    Путь к файловой информационной базе

.PARAMETER InfoBaseServer
    Сервер 1С (для серверной базы)

.PARAMETER InfoBaseRef
    Имя базы на сервере

.PARAMETER UserName
    Имя пользователя 1С

.PARAMETER Password
    Пароль пользователя

.PARAMETER PathXUnit
    Путь к xddTestRunner.epf

.PARAMETER OrdinaryApp
    Режим обычного приложения: 1 = да, 0 = нет (по умолчанию 1)

.PARAMETER ReportPath
    Путь к выходному JUnit XML (по умолчанию build/tests/junit.xml)

.PARAMETER SettingsFile
    Путь к файлу настроек vrunner (по умолчанию env.json)

.EXAMPLE
    .\xunit-run.ps1 -InfoBasePath "C:\Bases\MyDB" -UserName "test" -Password "1"

.EXAMPLE
    .\xunit-run.ps1 -TestPath "tests/MyTest.epf" -SettingsFile "env.json"
#>

[CmdletBinding()]
param(
    [string]$TestPath = "tests",
    [string]$V8Version,
    [string]$InfoBasePath,
    [string]$InfoBaseServer,
    [string]$InfoBaseRef,
    [string]$UserName,
    [string]$Password,
    [string]$PathXUnit,
    [int]$OrdinaryApp = 1,
    [string]$ReportPath = "build\tests\junit.xml",
    [string]$SettingsFile = "env.json"
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Find vrunner ---
function Find-Vrunner {
    # 1. PATH
    $cmd = Get-Command vrunner -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $cmd = Get-Command vrunner.bat -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 2. ovm current
    $ovmPath = Join-Path $env:LOCALAPPDATA "ovm\current\bin\vrunner.bat"
    if (Test-Path $ovmPath) { return $ovmPath }

    # 3. AppData Roaming
    $roamingPath = Join-Path $env:APPDATA "ovm\current\bin\vrunner.bat"
    if (Test-Path $roamingPath) { return $roamingPath }

    return $null
}

# --- Find xddTestRunner.epf ---
function Find-XddTestRunner {
    # Explicit parameter
    if ($PathXUnit -and (Test-Path $PathXUnit)) { return $PathXUnit }

    # Standard locations
    $candidates = @(
        "oscript_modules\add\xddTestRunner.epf",
        "oscript_modules\bin\xddTestRunner.epf",
        ".vrunner-cache\xddTestRunner.epf"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

# --- Auto-detect V8 version ---
function Find-V8Version {
    if ($V8Version) { return $V8Version }

    $found = Get-ChildItem "C:\Program Files\1cv8\*\bin\1cv8.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) {
        # Extract version from path: C:\Program Files\1cv8\8.3.27.1859\bin\1cv8.exe
        $parts = $found.FullName -split '\\'
        foreach ($p in $parts) {
            if ($p -match '^\d+\.\d+\.\d+\.\d+$') { return $p }
        }
    }
    return $null
}

# --- Build ibconnection string ---
function Build-IBConnection {
    if ($InfoBaseServer -and $InfoBaseRef) {
        return "/S`"$InfoBaseServer/$InfoBaseRef`""
    }
    if ($InfoBasePath) {
        return "/F$InfoBasePath"
    }
    return $null
}

# --- Parse JUnit XML and print summary ---
function Show-JUnitResults {
    param([string]$XmlPath)

    if (-not (Test-Path $XmlPath)) {
        Write-Host "[ERROR] JUnit report not found: $XmlPath" -ForegroundColor Red
        Write-Host "        vrunner completed but did not generate a report." -ForegroundColor Red
        Write-Host "        Possible causes: EPF contains syntax errors, xddTestRunner failed to load tests." -ForegroundColor Yellow
        return $false
    }

    [xml]$xml = Get-Content $XmlPath -Encoding UTF8
    $root = $xml.testsuites

    $total = [int]$root.tests
    $failures = [int]$root.failures
    $errors = [int]$root.errors
    $skipped = [int]$root.skipped
    $time = $root.time
    $passed = $total - $failures - $errors - $skipped

    # Summary
    Write-Host ""
    Write-Host "=== xUnit Results ===" -ForegroundColor Cyan
    Write-Host "Total: $total | " -NoNewline
    Write-Host "Passed: $passed" -ForegroundColor Green -NoNewline
    if ($failures -gt 0) {
        Write-Host " | Failed: $failures" -ForegroundColor Red -NoNewline
    } else {
        Write-Host " | Failed: $failures" -NoNewline
    }
    if ($errors -gt 0) {
        Write-Host " | Errors: $errors" -ForegroundColor Red -NoNewline
    } else {
        Write-Host " | Errors: $errors" -NoNewline
    }
    Write-Host " | Skipped: $skipped | Time: ${time}s"

    # Collect failed/error tests
    $problemTests = @()
    $allTests = $xml.SelectNodes("//testcase")
    foreach ($tc in $allTests) {
        $status = $tc.GetAttribute("status")
        if ($status -eq "failure" -or $status -eq "error") {
            $name = $tc.GetAttribute("name")
            $cls = $tc.GetAttribute("classname")
            $msg = ""
            $failNode = $tc.SelectSingleNode("failure")
            if (-not $failNode) { $failNode = $tc.SelectSingleNode("error") }
            if ($failNode) { $msg = $failNode.GetAttribute("message") }
            $problemTests += @{ Name = $name; Class = $cls; Message = $msg; Status = $status }
        }
    }

    if ($problemTests.Count -gt 0) {
        Write-Host ""
        Write-Host "--- Failed/Error Tests ---" -ForegroundColor Red
        foreach ($t in $problemTests) {
            $icon = if ($t.Status -eq "failure") { "FAIL" } else { "ERROR" }
            Write-Host "  [$icon] $($t.Class).$($t.Name)" -ForegroundColor Red
            if ($t.Message) {
                $shortMsg = ($t.Message -split "`n")[0]
                if ($shortMsg.Length -gt 200) { $shortMsg = $shortMsg.Substring(0, 200) + "..." }
                Write-Host "         $shortMsg" -ForegroundColor Yellow
            }
        }
    }

    if ($failures -eq 0 -and $errors -eq 0 -and $total -gt 0) {
        Write-Host ""
        if ($skipped -gt 0) {
            Write-Host "All executed tests passed! ($skipped skipped)" -ForegroundColor Green
        } else {
            Write-Host "All tests passed!" -ForegroundColor Green
        }
    }

    return ($failures -eq 0 -and $errors -eq 0)
}

# ============================================================
# Main
# ============================================================

# 1. Find vrunner
$vrunner = Find-Vrunner
if (-not $vrunner) {
    Write-Host "[ERROR] vrunner not found. Install: opm install vanessa-runner" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] vrunner: $vrunner" -ForegroundColor Green

# 2. Check/generate env.json
$generateSettings = $false
if (Test-Path $SettingsFile) {
    Write-Host "[OK] Settings: $SettingsFile" -ForegroundColor Green

    # If connection params provided, update env.json
    if ($InfoBasePath -or ($InfoBaseServer -and $InfoBaseRef)) {
        $generateSettings = $true
    }
} else {
    if (-not $InfoBasePath -and (-not $InfoBaseServer -or -not $InfoBaseRef)) {
        Write-Host "[ERROR] No $SettingsFile found and no connection params provided." -ForegroundColor Red
        Write-Host "        Provide -InfoBasePath or -InfoBaseServer/-InfoBaseRef, or create $SettingsFile" -ForegroundColor Yellow
        exit 1
    }
    $generateSettings = $true
}

if ($generateSettings) {
    $ibconn = Build-IBConnection
    if (-not $ibconn) {
        Write-Host "[ERROR] Cannot build connection string" -ForegroundColor Red
        exit 1
    }

    $v8ver = Find-V8Version
    if (-not $v8ver) {
        Write-Host "[ERROR] Cannot determine V8 version. Specify -V8Version" -ForegroundColor Red
        exit 1
    }

    $xunit = Find-XddTestRunner
    if (-not $xunit -and $PathXUnit) { $xunit = $PathXUnit }
    if (-not $xunit) { $xunit = "oscript_modules\add\xddTestRunner.epf" }

    # Build settings object
    $settings = @{
        "default" = [ordered]@{
            "--v8version"    = $v8ver
            "--ibconnection" = $ibconn
            "--db-user"      = if ($UserName) { $UserName } else { "" }
            "--db-pwd"       = if ($Password) { $Password } else { "" }
            "--pathxunit"    = $xunit
            "--ordinaryapp"  = "$OrdinaryApp"
            "--additional"   = "/DisableUnsafeActionProtection"
            "--reportsxunit" = "ГенераторОтчетаJUnitXML{$ReportPath}"
        }
    }

    $json = $settings | ConvertTo-Json -Depth 3
    $resolvedPath = $SettingsFile
    $rp = Resolve-Path $SettingsFile -ErrorAction SilentlyContinue
    if ($rp) { $resolvedPath = $rp.Path }
    [IO.File]::WriteAllText($resolvedPath, $json, (New-Object System.Text.UTF8Encoding $true))
    Write-Host "[OK] Generated: $SettingsFile" -ForegroundColor Green
}

# 3. Check xddTestRunner.epf
$xunitRunner = Find-XddTestRunner
if (-not $xunitRunner) {
    # Try to read from env.json
    $envContent = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $pathFromEnv = $envContent.default.PSObject.Properties['--pathxunit'].Value
    if ($pathFromEnv -and (Test-Path $pathFromEnv)) {
        $xunitRunner = $pathFromEnv
    }
}
if (-not $xunitRunner -or -not (Test-Path $xunitRunner)) {
    Write-Host "[ERROR] xddTestRunner.epf not found." -ForegroundColor Red
    Write-Host "        Install: opm install add" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] xddTestRunner: $xunitRunner" -ForegroundColor Green

# 4. Ensure report directory exists
$reportDir = Split-Path $ReportPath -Parent
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

# Remove old report
if (Test-Path $ReportPath) { Remove-Item $ReportPath -Force }

# 5. Validate test path
if (-not (Test-Path $TestPath)) {
    Write-Host "[ERROR] Test path not found: $TestPath" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Tests: $TestPath" -ForegroundColor Green

# 6. Run vrunner xunit
Write-Host ""
Write-Host "Running: vrunner xunit --settings $SettingsFile `"$TestPath`"" -ForegroundColor Cyan
Write-Host ""

# IMPORTANT: test path is a POSITIONAL argument, NOT --testpath
& $vrunner xunit --settings $SettingsFile "$TestPath"
$vrunnerExit = $LASTEXITCODE

# 7. Parse and show results
$allPassed = Show-JUnitResults -XmlPath $ReportPath

if ($allPassed) {
    exit 0
} else {
    exit 1
}
