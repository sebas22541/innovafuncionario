param(
  [string]$BackendBaseUrl = "https://innovafuncionarioapidev.cochabamba.bo",
  [string]$EnvFile,
  [string]$OutputDir
)

$ErrorActionPreference = "Stop"

$frontendRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoRoot = Resolve-Path (Join-Path $frontendRoot "..")

if ([string]::IsNullOrWhiteSpace($EnvFile)) {
  $EnvFile = Join-Path $repoRoot "backend\.env.dev"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = $repoRoot
}

function Read-DotEnvValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "No existe el archivo de entorno: $Path"
  }

  $escapedName = [regex]::Escape($Name)
  $line = Get-Content -LiteralPath $Path |
    Where-Object { $_ -match "^\s*$escapedName\s*=" -and $_ -notmatch "^\s*#" } |
    Select-Object -Last 1

  if ($null -eq $line) {
    return $null
  }

  $value = ($line -split "=", 2)[1].Trim()

  if (
    ($value.StartsWith('"') -and $value.EndsWith('"')) -or
    ($value.StartsWith("'") -and $value.EndsWith("'"))
  ) {
    $value = $value.Substring(1, $value.Length - 2)
  }

  return $value
}

$payloadEncryptionKey = Read-DotEnvValue -Path $EnvFile -Name "PAYLOAD_ENCRYPTION_KEY"

if ([string]::IsNullOrWhiteSpace($payloadEncryptionKey)) {
  throw "PAYLOAD_ENCRYPTION_KEY no esta definido en $EnvFile"
}

Push-Location $frontendRoot
try {
  $buildOutput = & flutter build apk --release `
    --dart-define=BACKEND_BASE_URL=$BackendBaseUrl `
    --dart-define=PAYLOAD_ENCRYPTION_KEY=$payloadEncryptionKey 2>&1
  $buildExitCode = $LASTEXITCODE

  $buildOutput | ForEach-Object {
    ($_ -replace "(-Pdart-defines=)[^\s]+", '$1<oculto>')
  }

  if ($buildExitCode -ne 0) {
    throw "flutter build apk fallo con codigo $buildExitCode"
  }
} finally {
  Pop-Location
}

$versionLine = Get-Content -LiteralPath (Join-Path $frontendRoot "pubspec.yaml") |
  Where-Object { $_ -match "^\s*version\s*:" } |
  Select-Object -First 1
$version = (($versionLine -split ":", 2)[1]).Trim().Replace("+", "_")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$apkName = "innovafuncionario-dev-$version-apidev-$timestamp.apk"
$apkSource = Join-Path $frontendRoot "build\app\outputs\flutter-apk\app-release.apk"
$apkDestination = Join-Path $OutputDir $apkName

Copy-Item -LiteralPath $apkSource -Destination $apkDestination -Force

$hash = Get-FileHash -Algorithm SHA1 -LiteralPath $apkDestination
$hash.Hash | Set-Content -LiteralPath "$apkDestination.sha1" -NoNewline

Write-Host "APK dev generado: $apkDestination"
Write-Host "SHA1: $($hash.Hash)"
