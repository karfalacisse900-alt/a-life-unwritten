param([string]$OutputPath = 'C:\Users\The-s\Documents\ChatGPT\gamei\a-life-unwritten\A-Life-Unwritten-Xogot.zip')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputFile = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $outputFile) { throw "Output already exists; use a new output path: $outputFile" }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archiveStream = [IO.File]::Open($outputFile, [IO.FileMode]::CreateNew)
$archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create)
try {
    $sourceFiles = @('project.godot', 'main.tscn', 'README.md', 'XOGOT.md', 'ARCHITECTURE.md') | ForEach-Object { Get-Item -LiteralPath (Join-Path $projectRoot $_) }
    foreach ($sourceDirectory in @('scripts', 'data', 'assets', 'tests')) {
        $sourceFiles += Get-ChildItem -LiteralPath (Join-Path $projectRoot $sourceDirectory) -Recurse -File |
            Where-Object { $_.Extension -ne '.import' }
    }
    foreach ($sourceFile in $sourceFiles) {
        $relativePath = $sourceFile.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
        # Unused old full-page concept art is not part of the playable UI.
        if ($relativePath.StartsWith('assets/editorial/') -and $sourceFile.Name -ne 'people-portraits.png') { continue }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $sourceFile.FullName, "A Life Unwritten/$relativePath", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose(); $archiveStream.Dispose() }
Get-Item -LiteralPath $outputFile | Select-Object FullName, Length
