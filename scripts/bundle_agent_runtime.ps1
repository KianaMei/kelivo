# bundle_agent_runtime.ps1
# Downloads and bundles Node.js runtime for Windows agent functionality
#
# Usage: .\bundle_agent_runtime.ps1 [-NodeVersion "22.16.0"]

param(
    [string]$NodeVersion = "22.16.0",
    [string]$OutputDir = $null
)

$ErrorActionPreference = "Stop"

# Determine paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$DefaultOutputDir = Join-Path $ProjectRoot "resources\agent-runtime"
$OutputDir = if ($OutputDir) { $OutputDir } else { $DefaultOutputDir }
$AgentBridgeSource = Join-Path $ProjectRoot "assets\agent-bridge"

# Node.js download URL
$NodeArch = "win-x64"
$NodeZipName = "node-v$NodeVersion-$NodeArch.zip"
$NodeUrl = "https://nodejs.org/dist/v$NodeVersion/$NodeZipName"
$NodeDir = Join-Path $OutputDir $NodeArch

Write-Host "Kelivo Agent Runtime Bundler for Windows"
Write-Host "=========================================="
Write-Host "Node.js Version: $NodeVersion"
Write-Host "Output Directory: $OutputDir"
Write-Host ""

# Create output directory
if (-not (Test-Path $OutputDir)) {
    Write-Host "Creating output directory..."
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Create platform-specific directory
if (-not (Test-Path $NodeDir)) {
    New-Item -ItemType Directory -Path $NodeDir -Force | Out-Null
}

# Download Node.js if not already present
$NodeExe = Join-Path $NodeDir "node.exe"
if (-not (Test-Path $NodeExe)) {
    $TempDir = Join-Path $env:TEMP "kelivo-agent-bundle"
    $ZipPath = Join-Path $TempDir $NodeZipName

    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }

    if (-not (Test-Path $ZipPath)) {
        Write-Host "Downloading Node.js $NodeVersion..."
        Write-Host "URL: $NodeUrl"

        try {
            # Use TLS 1.2 for HTTPS
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $NodeUrl -OutFile $ZipPath -UseBasicParsing
            Write-Host "Download complete."
        }
        catch {
            Write-Error "Failed to download Node.js: $_"
            exit 1
        }
    }
    else {
        Write-Host "Using cached Node.js archive..."
    }

    # Extract Node.js
    Write-Host "Extracting Node.js..."
    $ExtractDir = Join-Path $TempDir "node-v$NodeVersion-$NodeArch"

    if (Test-Path $ExtractDir) {
        Remove-Item -Recurse -Force $ExtractDir
    }

    try {
        Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force

        # Copy node.exe to output
        $SourceNodeExe = Join-Path $ExtractDir "node.exe"
        if (Test-Path $SourceNodeExe) {
            Copy-Item $SourceNodeExe $NodeExe -Force
            Write-Host "Node.exe copied to: $NodeExe"
        }
        else {
            Write-Error "node.exe not found in extracted archive at: $SourceNodeExe"
            exit 1
        }
    }
    catch {
        Write-Error "Failed to extract Node.js: $_"
        exit 1
    }
}
else {
    Write-Host "Node.js already present, skipping download."
}

# Copy agent-bridge files
$AgentBridgeOutput = Join-Path $OutputDir "agent-bridge"
Write-Host ""
Write-Host "Copying agent-bridge files..."

if (Test-Path $AgentBridgeOutput) {
    Remove-Item -Recurse -Force $AgentBridgeOutput
}

try {
    # Copy entire agent-bridge directory
    Copy-Item -Path $AgentBridgeSource -Destination $AgentBridgeOutput -Recurse -Force

    # Remove unnecessary files to reduce size
    $UnnecessaryFiles = @(
        "package-lock.json",
        ".npmrc",
        ".gitignore"
    )

    foreach ($file in $UnnecessaryFiles) {
        $filePath = Join-Path $AgentBridgeOutput $file
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force
        }
    }

    Write-Host "Agent-bridge files copied."
}
catch {
    Write-Error "Failed to copy agent-bridge files: $_"
    exit 1
}

# Calculate sizes
$NodeSize = (Get-Item $NodeExe).Length / 1MB
$BridgeSize = (Get-ChildItem -Path $AgentBridgeOutput -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
$TotalSize = $NodeSize + $BridgeSize

Write-Host ""
Write-Host "=========================================="
Write-Host "Bundle complete!"
Write-Host "  Node.js:      $([math]::Round($NodeSize, 2)) MB"
Write-Host "  Agent-bridge: $([math]::Round($BridgeSize, 2)) MB"
Write-Host "  Total:        $([math]::Round($TotalSize, 2)) MB"
Write-Host ""
Write-Host "Output: $OutputDir"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Run 'flutter build windows --release'"
Write-Host "2. Copy $OutputDir to the build output"
Write-Host "   (build\windows\x64\runner\Release\data\agent-runtime)"
