param(
	[Parameter(Mandatory = $true)]
	[string]$ArtifactDirectory,
	[string]$VendorPath = "vendor/machina"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageName = "machina-roblox"

function Get-SingleFile([string]$pattern) {
	$matches = @(Get-ChildItem -Path $ArtifactDirectory -Filter $pattern -File)
	if ($matches.Count -ne 1) {
		throw "Expected exactly one file matching '$pattern' in $ArtifactDirectory, found $($matches.Count)."
	}
	return $matches[0]
}

$metadataFile = Get-SingleFile "machina-release-metadata-*.json"
$archiveFile = Get-SingleFile "$packageName-*.tar.gz"
$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("machina-import-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

try {
	$metadata = Get-Content -Raw -Path $metadataFile.FullName | ConvertFrom-Json
	$artifact = $metadata.artifacts | Select-Object -ExpandProperty $packageName
	$actualHash = (Get-FileHash -Path $archiveFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
	$expectedHash = $artifact.sha256.ToLowerInvariant()

	if ($actualHash -ne $expectedHash) {
		throw "Checksum mismatch for $($archiveFile.Name). Expected $expectedHash but got $actualHash."
	}

	& tar -xzf $archiveFile.FullName -C $extractRoot
	if ($LASTEXITCODE -ne 0) {
		throw "Failed to extract $($archiveFile.Name)"
	}

	$resolvedVendorPath = if ([System.IO.Path]::IsPathRooted($VendorPath)) {
		$VendorPath
	} else {
		Join-Path (Get-Location) $VendorPath
	}

	$packageRoot = Join-Path $extractRoot $packageName
	if (-not (Test-Path $packageRoot)) {
		throw "Extracted archive did not contain expected package root '$packageName'"
	}

	if (Test-Path $resolvedVendorPath) {
		Remove-Item -Recurse -Force $resolvedVendorPath
	}

	New-Item -ItemType Directory -Force -Path $resolvedVendorPath | Out-Null
	Copy-Item -Recurse -Force -Path (Join-Path $packageRoot "*") -Destination $resolvedVendorPath

	[ordered]@{
		package = $packageName
		version = $metadata.version
		gitRef = $metadata.gitRef
		importedAtUtc = [DateTime]::UtcNow.ToString("o")
		artifactDirectory = (Resolve-Path $ArtifactDirectory).Path
	} | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $resolvedVendorPath ".machina-import.json")
} finally {
	if (Test-Path $extractRoot) {
		Remove-Item -Recurse -Force $extractRoot
	}
}
