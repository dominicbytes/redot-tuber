param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pluginConfig = Join-Path $repositoryRoot "addons\redot-tuber\plugin.cfg"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $match = [regex]::Match([System.IO.File]::ReadAllText($pluginConfig), 'version="([^"]+)"')
    if (-not $match.Success) {
        throw "Unable to read the Redot Tuber version from plugin.cfg"
    }
    $Version = $match.Groups[1].Value
}
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Invalid package version: $Version"
}

$outputDirectory = Join-Path $repositoryRoot "dist"
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $outputDirectory "redot-tuber-$Version.zip"))
$checksumPath = [System.IO.Path]::GetFullPath("$archivePath.sha256")
$safeOutputPrefix = [System.IO.Path]::GetFullPath($outputDirectory).TrimEnd('\') + '\'
if (-not $archivePath.StartsWith($safeOutputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Package output escaped the repository dist directory"
}

[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
foreach ($generatedPath in @($archivePath, $checksumPath)) {
    if (Test-Path -LiteralPath $generatedPath) {
        Remove-Item -LiteralPath $generatedPath -Force
    }
}

$includeDirectories = @("addons", "docs", "examples", "native", "tools")
$includeFiles = @(".gitignore", "CHANGELOG.md", "LICENSE", "project.godot", "README.md", "THIRD_PARTY_NOTICES.md")
$sourceFiles = @()
foreach ($directoryName in $includeDirectories) {
    $directoryPath = Join-Path $repositoryRoot $directoryName
    $sourceFiles += Get-ChildItem -LiteralPath $directoryPath -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.tools[\\/]' -and $_.Name -notmatch '^(?:.*\.test(?:\.exe)?|coverage\.out)$'
    }
}
foreach ($filename in $includeFiles) {
    $sourceFiles += Get-Item -LiteralPath (Join-Path $repositoryRoot $filename)
}
$sourceFiles = $sourceFiles | Sort-Object FullName -Unique
$sourcePrefix = $repositoryRoot.TrimEnd('\') + '\'

Add-Type -AssemblyName System.IO.Compression
$archiveStream = [System.IO.File]::Open($archivePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$archive = $null
try {
    $archive = [System.IO.Compression.ZipArchive]::new($archiveStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    foreach ($sourceFile in $sourceFiles) {
        if (-not $sourceFile.FullName.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package input escaped the repository root: $($sourceFile.FullName)"
        }
        $relativePath = $sourceFile.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
        $entry = $archive.CreateEntry($relativePath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $sourceFile.LastWriteTimeUtc
        $unixMode = 33261 # regular file, 0755
        if ($relativePath -notin @("addons/redot-tuber/bin/linux/x86_64/redot-tuber-credential-helper", "addons/redot-tuber/bin/linux/x86_64/redot-tuber-stream-helper")) {
            $unixMode = 33188 # regular file, 0644
        }
        $entry.ExternalAttributes = [int]($unixMode -shl 16)
        $inputStream = [System.IO.File]::OpenRead($sourceFile.FullName)
        $entryStream = $entry.Open()
        try {
            $inputStream.CopyTo($entryStream)
        }
        finally {
            $entryStream.Dispose()
            $inputStream.Dispose()
        }
    }
}
finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }
    $archiveStream.Dispose()
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText($checksumPath, "$hash  $([System.IO.Path]::GetFileName($archivePath))`n", [System.Text.UTF8Encoding]::new($false))

[PSCustomObject]@{
    Archive = $archivePath
    Sha256 = $hash
    Files = $sourceFiles.Count
    Bytes = (Get-Item -LiteralPath $archivePath).Length
}
