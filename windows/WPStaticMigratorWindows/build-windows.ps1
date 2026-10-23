param(
    [string]$RuntimeIdentifier = "win-x64",
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Resolve-Path (Join-Path $ProjectDir "..\..")
$RuntimeDir = Join-Path $ProjectDir "Runtime"
$RuntimeBundle = Join-Path $ProjectDir "RuntimeBundle.zip"
$PublishDir = Join-Path $ProjectDir "publish\$RuntimeIdentifier"
$DistDir = Join-Path $ProjectDir "dist"
$Archive = Join-Path $DistDir "WP-Static-Migrator-v$Version-Windows-x64.zip"

Write-Host "Installing production Node.js dependencies..."
Push-Location $RepositoryRoot
try {
    npm ci --omit=dev
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

if (Test-Path $RuntimeDir) { Remove-Item $RuntimeDir -Recurse -Force }
New-Item $RuntimeDir -ItemType Directory | Out-Null
Copy-Item (Join-Path $RepositoryRoot "bin") $RuntimeDir -Recurse
Copy-Item (Join-Path $RepositoryRoot "scripts") $RuntimeDir -Recurse
Copy-Item (Join-Path $RepositoryRoot "node_modules") $RuntimeDir -Recurse
Copy-Item (Join-Path $RepositoryRoot "package.json") $RuntimeDir
Copy-Item (Join-Path $RepositoryRoot "config.json") $RuntimeDir
New-Item (Join-Path $RuntimeDir "src\layouts") -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $RepositoryRoot "src\layouts\default.html") (Join-Path $RuntimeDir "src\layouts\default.html")
Copy-Item (Join-Path $RepositoryRoot "LICENSE.md") $RuntimeDir -ErrorAction SilentlyContinue

if (Test-Path $RuntimeBundle) { Remove-Item $RuntimeBundle -Force }
Compress-Archive -Path (Join-Path $RuntimeDir "*") -DestinationPath $RuntimeBundle -CompressionLevel Optimal

Write-Host "Publishing self-contained Windows application..."
if (Test-Path $PublishDir) { Remove-Item $PublishDir -Recurse -Force }
dotnet publish (Join-Path $ProjectDir "WPStaticMigratorWindows.csproj") `
    -c Release -r $RuntimeIdentifier --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None -p:DebugSymbols=false -p:Version=$Version -o $PublishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

if (-not (Test-Path (Join-Path $PublishDir "WP Static Migrator.exe"))) {
    throw "Published application was not found in $PublishDir"
}

$UnexpectedFiles = Get-ChildItem $PublishDir -File | Where-Object { $_.Name -ne "WP Static Migrator.exe" }
if ($UnexpectedFiles) {
    throw "Unexpected files were published: $($UnexpectedFiles.Name -join ', ')"
}

New-Item $DistDir -ItemType Directory -Force | Out-Null
if (Test-Path $Archive) { Remove-Item $Archive -Force }
Compress-Archive -Path (Join-Path $PublishDir "*") -DestinationPath $Archive -CompressionLevel Optimal
Write-Host "Created: $Archive"
