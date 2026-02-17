param(
    [ValidateSet("run-profile", "run-profile-trace", "build-profile-apk", "build-release-apk", "all")]
    [string]$Task = "all",
    [string]$DeviceId = "",
    [switch]$SkipPubGet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    Write-Host ">> flutter $($Args -join ' ')" -ForegroundColor Cyan
    & flutter @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: flutter $($Args -join ' ')"
    }
}

Push-Location (Join-Path $PSScriptRoot "..")
try {
    Invoke-Flutter -Args @("--version")

    if (-not $SkipPubGet) {
        Invoke-Flutter -Args @("pub", "get")
    }

    switch ($Task) {
        "run-profile" {
            if ([string]::IsNullOrWhiteSpace($DeviceId)) {
                throw "DeviceId is required for run-profile. Example: .\tool\perf_checks.ps1 -Task run-profile -DeviceId emulator-5554"
            }

            Invoke-Flutter -Args @(
                "run",
                "--profile",
                "-d",
                $DeviceId
            )
        }

        "run-profile-trace" {
            if ([string]::IsNullOrWhiteSpace($DeviceId)) {
                throw "DeviceId is required for run-profile-trace. Example: .\tool\perf_checks.ps1 -Task run-profile-trace -DeviceId emulator-5554"
            }

            Invoke-Flutter -Args @(
                "run",
                "--profile",
                "--trace-skia",
                "-d",
                $DeviceId
            )
        }

        "build-profile-apk" {
            Invoke-Flutter -Args @(
                "build",
                "apk",
                "--profile"
            )
        }

        "build-release-apk" {
            Invoke-Flutter -Args @(
                "build",
                "apk",
                "--release",
                "--analyze-size",
                "--split-debug-info=build/symbols/android"
            )
        }

        "all" {
            Invoke-Flutter -Args @(
                "build",
                "apk",
                "--profile"
            )

            Invoke-Flutter -Args @(
                "build",
                "apk",
                "--release",
                "--analyze-size",
                "--split-debug-info=build/symbols/android"
            )
        }
    }

    Write-Host ""
    Write-Host "Performance checks completed in non-debug mode." -ForegroundColor Green
} finally {
    Pop-Location
}
