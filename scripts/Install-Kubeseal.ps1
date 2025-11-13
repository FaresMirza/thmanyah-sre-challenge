# -------------------------------------------
# Install Kubeseal for Windows (Fixed + Stable)
# -------------------------------------------

Write-Host "Initializing TLS 1.2..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installDir = "C:\bin\kubeseal"
$tempFile   = "$env:TEMP\kubeseal.tar.gz"

# Create install directory
Write-Host "Creating the '$installDir' directory..."
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# Download release metadata
Write-Host "Retrieving releases from GitHub API..."
$releasesResponse = Invoke-WebRequest -UseBasicParsing `
    -Uri "https://api.github.com/repos/bitnami-labs/sealed-secrets/releases"

if (-not $releasesResponse) {
    Write-Host "ERROR: Failed to fetch releases."
    exit 1
}

$releases = $releasesResponse.Content | ConvertFrom-Json

# Find Windows binary
Write-Host "Finding latest Windows release..."
$asset = $releases[0].assets | Where-Object { $_.name -like "*windows-amd64.tar.gz" }

if (-not $asset) {
    Write-Host "ERROR: Could not find Windows kubeseal asset."
    exit 1
}

$downloadUrl = $asset.browser_download_url
Write-Host "Downloading kubeseal from:"
Write-Host "  $downloadUrl"

Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $tempFile

# Extract archive
Write-Host "Extracting kubeseal..."
tar -xf $tempFile -C $installDir

# Clean up
Remove-Item $tempFile -Force

# Find kubeseal.exe (auto-detect location)
Write-Host "Searching for kubeseal.exe..."
$kubesealPath = Get-ChildItem -Path $installDir -Recurse -Filter "kubeseal.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $kubesealPath) {
    Write-Host "ERROR: kubeseal.exe not found after extraction."
    exit 1
}

# Move kubeseal.exe to installDir root
$targetExe = Join-Path $installDir "kubeseal.exe"
if ($kubesealPath.FullName -ne $targetExe) {
    Write-Host "Moving kubeseal.exe to $installDir..."
    Move-Item -Path $kubesealPath.FullName -Destination $targetExe -Force
}

# Add to PATH if needed
if (-not ($env:Path -like "*$installDir*")) {
    Write-Host "Adding '$installDir' to PATH..."
    setx PATH "$env:Path;$installDir" | Out-Null
}

# Refresh PATH for current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";$installDir"

# Test
Write-Host "Testing kubeseal installation..."
try {
    kubeseal --version
    Write-Host "`n🎉 Kubeseal installed successfully!"
} catch {
    Write-Host "⚠️ kubeseal installed but not detected in current session."
    Write-Host "➡️ Please open a NEW PowerShell window and run: kubeseal --version"
}
