param(
    [string]$RuntimeIdentifier = "win-x64",
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Resolve-Path (Join-Path $ProjectDir "..\..")
$RuntimeDir = Join-Path $ProjectDir "Runtime"
$PublishDir = Join-Path $ProjectDir "publish\$RuntimeIdentifier"
$DistDir = Join-Path $ProjectDir "dist"
$Archive = Join-Path $DistDir "WP-Static-Migrator-v$Version-Windows-x64.zip"

Write-Host "Installing production Node.js dependencies..."
Push-Location $RepositoryRoot
try { npm ci --omit=dev } finally { Pop-Location }

if (Test-Path $RuntimeDir) { Remove-Item $RuntimeDir -Recurse -Force }
New-Item $RuntimeDir -ItemType Directory | Out-Null
Copy-Item (Join-Path $RepositoryRoot "bin") $RuntimeDir -Recurse
Copy-Item (Join-Path $RepositoryRoot "scripts") $RuntimeDir -Recurse
Copy-Item (Join-Path $RepositoryRoot "node_modules") $RuntimeDir -Recurse
Copy-Item (Join-Path $RepositoryRoot "package.json") $RuntimeDir
Copy-Item (Join-Path $RepositoryRoot "LICENSE") $RuntimeDir -ErrorAction SilentlyContinue

Write-Host "Publishing self-contained Windows application..."
dotnet publish (Join-Path $ProjectDir "WPStaticMigratorWindows.csproj") `
    -c Release -r $RuntimeIdentifier --self-contained true `
    -p:PublishSingleFile=false -p:Version=$Version -o $PublishDir

New-Item $DistDir -ItemType Directory -Force | Out-Null
if (Test-Path $Archive) { Remove-Item $Archive -Force }
Compress-Archive -Path (Join-Path $PublishDir "*") -DestinationPath $Archive -CompressionLevel Optimal
Write-Host "Created: $Archive"
