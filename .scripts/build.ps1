# ============================================================================
# WPZylos Scaffold - Build Script
# ============================================================================
# Creates a production-ready distributable ZIP with PHP-Scoper isolation.
# Reads configuration from .plugin-config.json (created by init-plugin.ps1).
#
# Build Pipeline:
#   1. Clean build artifacts
#   2. Run code style fix (phpcbf)
#   3. Run static analysis (phpstan)
#   4. Install production dependencies
#   5. Run PHP-Scoper
#   6. Copy required files
#   7. Create versioned ZIP
#
# Location: .scripts/build.ps1
# Called by: ../wpzylos.ps1
# ============================================================================

param(
    [switch]$Clean,
    [switch]$SkipQA,
    [switch]$SkipScoper,
    [string]$Version,
    [string]$PhpStanMemoryLimit = "2G",
    [string]$IntegrityUpdateUrl,
    [string]$IntegrityUpdateToken
)

# ============================================================================
# Change to project root (parent of .scripts)
# ============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Push-Location $projectRoot

# ============================================================================
# Configuration
# ============================================================================

$BUILD_DIR = Join-Path $projectRoot "build"
$DIST_DIR = Join-Path $projectRoot "dist"
$CONFIG_FILE = ".plugin-config.json"

# Load plugin config
if (Test-Path $CONFIG_FILE)
{
    $config = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
    $PLUGIN_SLUG = $config.plugin.slug
    $PLUGIN_NAME = $config.plugin.name
    $PLUGIN_NAMESPACE = $config.plugin.namespace
    $MAIN_FILE = $config.plugin.mainFile

    # Use version from config unless overridden
    if ( [string]::IsNullOrWhiteSpace($Version))
    {
        $Version = $config.plugin.version
    }
}
else
{
    # Fallback: Auto-detect from files
    Write-Host "Warning: .plugin-config.json not found. Using auto-detection." -ForegroundColor Yellow
    Write-Host "Run init-plugin.ps1 first for best results." -ForegroundColor Yellow
    Write-Host ""

    $mainPluginFile = Get-ChildItem -Filter "*.php" -File | Where-Object {
        $_.Name -ne "uninstall.php" -and
                $_.Name -ne "scoper.inc.php" -and
                $_.Name -notmatch "^index$.php$"
    } | Select-Object -First 1

    if (-not $mainPluginFile)
    {
        Write-Host "Error: Could not find main plugin file." -ForegroundColor Red
        exit 1
    }

    $PLUGIN_SLUG = $mainPluginFile.BaseName
    $MAIN_FILE = $mainPluginFile.Name
    $PLUGIN_NAME = $PLUGIN_SLUG

    # Extract version from plugin file
    $pluginContent = Get-Content $mainPluginFile.FullName -Raw
    if ([string]::IsNullOrWhiteSpace($Version) -and $pluginContent -match "Version:\s*([0-9.]+)")
    {
        $Version = $matches[1]
    }
}

if ( [string]::IsNullOrWhiteSpace($Version))
{
    $Version = "1.0.0"
}
if ( [string]::IsNullOrWhiteSpace($IntegrityUpdateUrl))
{
    if ($config -and $config.build -and $config.build.integrityUpdateUrl)
    {
        $IntegrityUpdateUrl = [string]($config.build.integrityUpdateUrl)
    }
    elseif ($env:LICENSE_INTEGRITY_UPDATE_URL)
    {
        $IntegrityUpdateUrl = $env:LICENSE_INTEGRITY_UPDATE_URL
    }
    else
    {
        $IntegrityUpdateUrl = "https://license-verification.test/api/v1/plugin/integrity"
    }
}

if ( [string]::IsNullOrWhiteSpace($IntegrityUpdateToken))
{
    if ($config -and $config.build -and $config.build.integrityUpdateToken)
    {
        $IntegrityUpdateToken = [string]($config.build.integrityUpdateToken)
    }
    elseif ($env:LICENSE_INTEGRITY_UPDATE_TOKEN)
    {
        $IntegrityUpdateToken = $env:LICENSE_INTEGRITY_UPDATE_TOKEN
    }
}

# ============================================================================
# Intelligent Version Suggestion
# ============================================================================

function Get-SuggestedVersion
{
    param([string]$CurrentVersion, [string]$PluginSlug)

    # Check for existing ZIPs in dist/
    if (Test-Path $DIST_DIR)
    {
        $existingZips = Get-ChildItem -Path $DIST_DIR -Filter "$PluginSlug-*.zip" |
                Sort-Object Name -Descending

        if ($existingZips.Count -gt 0)
        {
            # Extract version from latest ZIP filename
            $latestZip = $existingZips[0].Name
            if ($latestZip -match "$PluginSlug-([0-9]+)\.([0-9]+)\.([0-9]+)\.zip")
            {
                $major = [int]$matches[1]
                $minor = [int]$matches[2]
                $patch = [int]$matches[3]

                # Suggest next patch version
                return "$major.$minor.$( $patch + 1 )"
            }
        }
    }

    # No existing ZIPs, suggest 1.0.0
    return "1.0.0"
}

# Only prompt if version wasn't passed via command line
if (-not $PSBoundParameters.ContainsKey('Version') -or [string]::IsNullOrWhiteSpace($PSBoundParameters['Version']))
{
    $suggestedVersion = Get-SuggestedVersion -CurrentVersion $Version -PluginSlug $PLUGIN_SLUG

    # Check if ZIP already exists for current version
    $currentZipPath = "$DIST_DIR\$PLUGIN_SLUG-$Version.zip"
    if (Test-Path $currentZipPath)
    {
        Write-Host ""
        Write-Host "  ZIP already exists for version $Version" -ForegroundColor Yellow
        Write-Host "  Suggested next version: " -NoNewline -ForegroundColor White
        Write-Host $suggestedVersion -ForegroundColor Cyan
        Write-Host ""
        $userVersion = Read-Host "  Version [$suggestedVersion]"
        if ( [string]::IsNullOrWhiteSpace($userVersion))
        {
            $Version = $suggestedVersion
        }
        else
        {
            $Version = $userVersion
        }
    }
    elseif ($Version -eq "1.0.0" -and $suggestedVersion -ne "1.0.0")
    {
        # Config has 1.0.0 but we have existing builds
        Write-Host ""
        Write-Host "  Existing builds found. Suggested version: " -NoNewline -ForegroundColor White
        Write-Host $suggestedVersion -ForegroundColor Cyan
        Write-Host ""
        $userVersion = Read-Host "  Version [$suggestedVersion]"
        if ( [string]::IsNullOrWhiteSpace($userVersion))
        {
            $Version = $suggestedVersion
        }
        else
        {
            $Version = $userVersion
        }
    }
}

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Step
{
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Yellow
}

function Write-Success
{
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning
{
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Error
{
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# ============================================================================
# Intelligent Build Config Functions
# ============================================================================

# Known items that should always be excluded from build
$ALWAYS_EXCLUDE = @(
    ".git", ".github", ".scripts", ".vite", ".gitignore", ".gitattributes",
    "vendor", "tests", "docs", "node_modules", "phpstan-stubs",
    "composer.lock", "phpstan.neon", "phpstan.neon.dist", "phpunit.xml",
    "scoper.inc.php", "scaffold.ps1", "scaffold.sh",
    "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md",
    ".plugin-config.json", "build", "dist", "raw"
)

# Base structure directories that should be auto-included
$BASE_STRUCTURE_DIRS = @("app", "bootstrap", "config", "database", "resources", "routes")

# Essential files that should be auto-included
$ESSENTIAL_FILES = @("uninstall.php", "readme.txt", "LICENSE", "composer.json")

function Get-BuildConfig
{
    if (Test-Path $CONFIG_FILE)
    {
        $cfg = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
        if ($cfg.build)
        {
            return $cfg.build
        }
    }
    return $null
}

function Save-BuildConfig
{
    param($BuildConfig)

    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (Test-Path $CONFIG_FILE)
    {
        $fullPath = (Resolve-Path $CONFIG_FILE).Path
        $cfg = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json

        # Merge build keys so integrity and future/custom settings survive.
        $cfgHash = @{ }
        $cfg.PSObject.Properties | ForEach-Object { $cfgHash[$_.Name] = $_.Value }
        $mergedBuild = @{ }
        if ($cfg.build)
        {
            $cfg.build.PSObject.Properties | ForEach-Object { $mergedBuild[$_.Name] = $_.Value }
        }
        if ($BuildConfig -is [System.Collections.IDictionary])
        {
            foreach ($key in $BuildConfig.Keys)
            {
                $mergedBuild[$key] = $BuildConfig[$key]
            }
        }
        else
        {
            $BuildConfig.PSObject.Properties | ForEach-Object { $mergedBuild[$_.Name] = $_.Value }
        }
        $cfgHash.build = $mergedBuild

        $json = $cfgHash | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($fullPath, $json, $Utf8NoBom)
    }
}

function Get-IncludedItems
{
    # Load saved build config or create new
    $buildConfig = Get-BuildConfig
    $needsSave = $false

    if (-not $buildConfig)
    {
        $buildConfig = @{
            includeDirs = @()
            includeFiles = @()
            promptedItems = @()
        }
        $needsSave = $true
    }

    # Ensure arrays exist
    if (-not $buildConfig.includeDirs)
    {
        $buildConfig.includeDirs = @()
    }
    if (-not $buildConfig.includeFiles)
    {
        $buildConfig.includeFiles = @()
    }
    if (-not $buildConfig.promptedItems)
    {
        $buildConfig.promptedItems = @()
    }

    # Scan root directory for files and folders
    $rootItems = Get-ChildItem -Path "." -Force | Where-Object {
        $_.Name -notin $ALWAYS_EXCLUDE -and
                $_.Name -ne $MAIN_FILE
    }

    $includeDirs = [System.Collections.ArrayList]@($buildConfig.includeDirs)
    $includeFiles = [System.Collections.ArrayList]@($buildConfig.includeFiles)
    $promptedItems = [System.Collections.ArrayList]@($buildConfig.promptedItems)

    # Process directories
    foreach ($item in ($rootItems | Where-Object { $_.PSIsContainer }))
    {
        $name = $item.Name

        # Auto-include base structure
        if ($name -in $BASE_STRUCTURE_DIRS)
        {
            if ($name -notin $includeDirs)
            {
                [void]$includeDirs.Add($name)
                $needsSave = $true
            }
        }
        # Prompt for unknown directories
        elseif ($name -notin $promptedItems)
        {
            Write-Host ""
            Write-Host "  Unknown directory found: " -NoNewline -ForegroundColor White
            Write-Host "$name/" -ForegroundColor Cyan
            $answer = Read-Host "  Include in build? [Y/n]"

            [void]$promptedItems.Add($name)
            if ($answer -ne 'n' -and $answer -ne 'N')
            {
                [void]$includeDirs.Add($name)
            }
            $needsSave = $true
        }
    }

    # Process PHP files at root (excluding known ones)
    $knownRootFiles = @($MAIN_FILE, "uninstall.php", "scoper.inc.php", "index.php")
    foreach ($item in ($rootItems | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq ".php" }))
    {
        $name = $item.Name

        if ($name -in $knownRootFiles)
        {
            continue
        }

        # Prompt for unknown PHP files
        if ($name -notin $promptedItems)
        {
            Write-Host ""
            Write-Host "  Unknown PHP file found: " -NoNewline -ForegroundColor White
            Write-Host "$name" -ForegroundColor Cyan
            $answer = Read-Host "  Include in build? [Y/n]"

            [void]$promptedItems.Add($name)
            if ($answer -ne 'n' -and $answer -ne 'N')
            {
                [void]$includeFiles.Add($name)
            }
            $needsSave = $true
        }
    }

    # Add essential files
    foreach ($file in $ESSENTIAL_FILES)
    {
        if ((Test-Path $file) -and $file -notin $includeFiles)
        {
            [void]$includeFiles.Add($file)
            $needsSave = $true
        }
    }

    # Always include main plugin file
    if ($MAIN_FILE -notin $includeFiles)
    {
        [void]$includeFiles.Add($MAIN_FILE)
        $needsSave = $true
    }

    # Save config if changed
    if ($needsSave)
    {
        $buildConfig = @{
            includeDirs = @($includeDirs | Sort-Object -Unique)
            includeFiles = @($includeFiles | Sort-Object -Unique)
            promptedItems = @($promptedItems | Sort-Object -Unique)
        }
        Save-BuildConfig -BuildConfig $buildConfig
        Write-Host ""
        Write-Host "  Build preferences saved to .plugin-config.json" -ForegroundColor Gray
    }

    return @{
        Dirs = @($includeDirs | Sort-Object -Unique)
        Files = @($includeFiles | Sort-Object -Unique)
    }
}

function Clean-Build
{
    Write-Step "Cleaning build artifacts..."

    if (Test-Path $BUILD_DIR)
    {
        Remove-Item -Path $BUILD_DIR -Recurse -Force
    }
    # Note: dist/ is preserved to keep previous ZIP builds

    Write-Success "Cleaned build directory"
}

function Run-PHPCBF
{
    Write-Step "Running PHP Code Beautifier (phpcbf --standard=PSR12)..."

    $phpcbfPath = "vendor\bin\phpcbf.bat"
    if (-not (Test-Path $phpcbfPath))
    {
        $phpcbfPath = "vendor\bin\phpcbf"
    }

    if (Test-Path $phpcbfPath)
    {
        # Run phpcbf - exit code 1 means files were fixed (not an error)
        $result = & $phpcbfPath --standard=PSR12 app 2>&1
        if ($LASTEXITCODE -eq 0)
        {
            Write-Success "No code style issues found"
        }
        elseif ($LASTEXITCODE -eq 1)
        {
            Write-Success "Code style issues auto-fixed"
        }
        else
        {
            Write-Warning "phpcbf returned exit code $LASTEXITCODE"
        }
    }
    else
    {
        Write-Warning "phpcbf not found. Skipping code style fix."
    }
}

function Run-PHPStan
{
    Write-Step "Running static analysis (phpstan analyze --memory-limit=$PhpStanMemoryLimit)..."

    $phpstanPath = "vendor\bin\phpstan.bat"
    if (-not (Test-Path $phpstanPath))
    {
        $phpstanPath = "vendor\bin\phpstan"
    }

    if (Test-Path $phpstanPath)
    {
        $result = & $phpstanPath analyze app --no-progress "--memory-limit=$PhpStanMemoryLimit" 2>&1
        if ($LASTEXITCODE -eq 0)
        {
            Write-Success "Static analysis passed"
        }
        else
        {
            Write-Error "Static analysis found issues:"
            Write-Host $result -ForegroundColor Gray
            $continue = Read-Host "Continue build anyway? [y/N]"
            if ($continue -ne 'y' -and $continue -ne 'Y')
            {
                exit 1
            }
        }
    }
    else
    {
        Write-Warning "phpstan not found. Skipping static analysis."
    }
}

function Copy-FrontendDist
{
    if (-not (Test-Path $DIST_DIR))
    {
        return
    }

    Write-Step "Copying frontend production assets..."

    $targetDir = Join-Path $BUILD_DIR "dist"
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

    Get-ChildItem -Path $DIST_DIR -Force | Where-Object {
        $_.Name -ne "temp" -and $_.Extension -ne ".zip"
    } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $targetDir -Recurse -Force
    }

    Write-Success "Frontend assets copied"
}

function Remove-FrontendSourceFiles
{
    $manifestPath = Join-Path $BUILD_DIR "dist\.vite\manifest.json"
    if (-not (Test-Path $manifestPath))
    {
        return
    }

    Write-Step "Removing frontend source files..."

    $sourceDirs = @(
        "$BUILD_DIR\resources\js",
        "$BUILD_DIR\resources\css",
        "$BUILD_DIR\resources\scss",
        "$BUILD_DIR\resources\sass",
        "$BUILD_DIR\resources\ts",
        "$BUILD_DIR\resources\tsx",
        "$BUILD_DIR\resources\vue",
        "$BUILD_DIR\resources\react"
    )

    foreach ($dir in $sourceDirs)
    {
        if (Test-Path $dir)
        {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Success "Frontend source files removed"
}

function Remove-LooseDistArtifacts
{
    if (-not (Test-Path $DIST_DIR))
    {
        return
    }

    Write-Step "Cleaning loose dist assets..."

    Get-ChildItem -Path $DIST_DIR -Force | Where-Object {
        $_.Extension -ne ".zip"
    } | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Success "Loose dist assets removed"
}

function Get-ReleaseIntegrityHash
{
    param([string]$PluginDir)

    $phpCode = @'
<?php
$root = rtrim(str_replace('\\', '/', $argv[1]), '/');
$productSlug = $argv[2];
$version = $argv[3];
$mainFile = $argv[4];
$paths = [$mainFile, 'app', 'resources/admin', 'resources/views', 'dist'];
$extensions = ['php' => true, 'js' => true, 'css' => true, 'vue' => true, 'json' => true];
$files = [];

$addFile = static function (string $absolutePath) use (&$files, $root, $extensions): void {
    $extension = strtolower(pathinfo($absolutePath, PATHINFO_EXTENSION));
    if (!isset($extensions[$extension])) {
        return;
    }

    $path = str_replace('\\', '/', $absolutePath);
    $relative = str_starts_with($path, $root) ? ltrim(substr($path, strlen($root)), '/') : basename($path);
    if ($relative !== '') {
        $files[$relative] = hash_file('sha256', $absolutePath);
    }
};

foreach ($paths as $relativePath) {
    $absolutePath = $root . '/' . $relativePath;

    if (is_file($absolutePath)) {
        $addFile($absolutePath);
        continue;
    }

    if (!is_dir($absolutePath)) {
        continue;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($absolutePath, FilesystemIterator::SKIP_DOTS)
    );

    foreach ($iterator as $file) {
        if ($file instanceof SplFileInfo && $file->isFile()) {
            $addFile($file->getPathname());
        }
    }
}

ksort($files);
$manifest = [
    'product_slug' => $productSlug,
    'version' => $version,
    'files' => $files,
];

echo hash('sha256', (string) json_encode($manifest));
'@

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("wpzylos-integrity-" + [System.Guid]::NewGuid().ToString("N") + ".php")
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempFile, $phpCode, $Utf8NoBom)

    try
    {
        $resolvedPluginDir = (Resolve-Path $PluginDir).Path
        $hash = & php $tempFile $resolvedPluginDir $PLUGIN_SLUG $Version $MAIN_FILE 2>&1

        if ($LASTEXITCODE -eq 0 -and "$hash" -match '^[a-f0-9]{64}$')
        {
            return "$hash"
        }
    }
    finally
    {
        if (Test-Path $tempFile)
        {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    return ""
}

function Update-BuildVersion
{
    $mainPath = Join-Path $BUILD_DIR $MAIN_FILE
    if (-not (Test-Path $mainPath))
    {
        Write-Error "Main plugin file is missing from build: $MAIN_FILE"
        exit 1
    }

    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $content = [System.IO.File]::ReadAllText($mainPath)
    $content = [regex]::Replace(
            $content,
            '(?m)^(\s*\*\s*Version:\s*)[^\r\n]+',
            { param($match) $match.Groups[1].Value + $Version }
    )
    $content = [regex]::Replace(
            $content,
            "('version'\s*=>\s*')[^']+(')",
            { param($match) $match.Groups[1].Value + $Version + $match.Groups[2].Value },
            1
    )
    [System.IO.File]::WriteAllText($mainPath, $content, $Utf8NoBom)

    $readmePath = Join-Path $BUILD_DIR 'readme.txt'
    if (Test-Path $readmePath)
    {
        $readme = [System.IO.File]::ReadAllText($readmePath)
        $readme = [regex]::Replace(
                $readme,
                '(?m)^(Stable tag:\s*)[^\r\n]+',
                { param($match) $match.Groups[1].Value + $Version }
        )
        [System.IO.File]::WriteAllText($readmePath, $readme, $Utf8NoBom)
    }

    Write-Success "Packaged plugin version set to $Version"
}

$script:IntegrityUpdatePerformed = $false

function Invoke-IntegrityUpdate
{
    param(
        [string]$IntegrityHash,
        [string]$PackageHash
    )

    if ( [string]::IsNullOrWhiteSpace($IntegrityUpdateUrl))
    {
        Write-Warning "Integrity update URL is not configured. Skipping license server update."
        return
    }

    if ( [string]::IsNullOrWhiteSpace($IntegrityUpdateToken))
    {
        Write-Warning "Integrity update token is not configured. Skipping license server update."
        return
    }

    if ( [string]::IsNullOrWhiteSpace($IntegrityHash))
    {
        Write-Error "Integrity hash is empty. Cannot update license server."
        exit 1
    }

    Write-Step "Updating license server integrity hash..."

    $payload = @{
        product_slug = $PLUGIN_SLUG
        integrity_hash = $IntegrityHash
        update_token = $IntegrityUpdateToken
        package_sha256 = $PackageHash
        version = $Version
        integrity_notes = "Updated by WPZylos build"
    }

    $oldCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    try
    {
        $uri = [Uri]$IntegrityUpdateUrl

        if ($uri.Host -eq "localhost" -or $uri.Host.EndsWith(".test") -or $uri.Host.EndsWith(".local"))
        {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }

        $response = Invoke-RestMethod `
            -Uri $IntegrityUpdateUrl `
            -Method Post `
            -ContentType "application/json" `
            -Body ($payload | ConvertTo-Json -Depth 4)

        if (-not $response.success)
        {
            Write-Error "License server integrity update failed"
            Write-Host ($response | ConvertTo-Json -Depth 4) -ForegroundColor Gray
            exit 1
        }

        Write-Success "License server integrity hash updated"
        $script:IntegrityUpdatePerformed = $true
    }
    catch
    {
        Write-Error "License server integrity update failed"
        Write-Host $_.Exception.Message -ForegroundColor Gray
        exit 1
    }
    finally
    {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $oldCallback
    }
}

# ============================================================================
# Main Build Process
# ============================================================================

"WPZylos Build - $PLUGIN_SLUG v$Version"

# Clean only mode
if ($Clean)
{
    Clean-Build
    exit 0
}

# Step 1: Clean
Clean-Build

# Step 2: Run QA (unless skipped)
if (-not $SkipQA)
{
    # Ensure dev dependencies are installed for QA tools
    Write-Step "Ensuring dev dependencies are installed..."

    Start-Sleep -Seconds 2

    $devComposerResult = & cmd.exe /d /c "composer.bat install --no-interaction --no-progress --no-ansi 2>&1"
    $devComposerExitCode = $LASTEXITCODE

    if ($devComposerExitCode -ne 0)
    {
        Write-Error "Composer dev install failed"
        if ($devComposerResult)
        {
            Write-Host ($devComposerResult -join [Environment]::NewLine) -ForegroundColor Gray
        }
        exit 1
    }

    Write-Success "Dependencies ready"

    Run-PHPCBF
    Run-PHPStan
}
else
{
    Write-Step "Skipping QA checks..."
}

# Step 3: Install production dependencies
Write-Step "Installing production dependencies..."

Start-Sleep -Seconds 2

$composerResult = & cmd.exe /d /c "composer.bat install --no-dev --prefer-dist --no-progress --no-interaction --no-ansi --optimize-autoloader --classmap-authoritative 2>&1"
$composerExitCode = $LASTEXITCODE

if ($composerExitCode -ne 0)
{
    Write-Error "Composer install failed"
    if ($composerResult)
    {
        Write-Host ($composerResult -join [Environment]::NewLine) -ForegroundColor Gray
    }
    exit 1
}

Write-Success "Production dependencies installed"

# Step: Build frontend assets
Write-Host "Building frontend assets..." -ForegroundColor Cyan
if (Test-Path "package.json")
{
    npm install --silent
    npm run build
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Frontend build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Frontend assets built." -ForegroundColor Green
}

# Step 4: Run PHP-Scoper (unless skipped)
if (-not $SkipScoper)
{
    Write-Step "Running PHP-Scoper..."

    # Re-install dev deps for scoper
    Start-Sleep -Seconds 2

    $devComposerResult = & cmd.exe /d /c "composer.bat install --no-interaction --no-progress --no-ansi 2>&1"
    $devComposerExitCode = $LASTEXITCODE

    if ($devComposerExitCode -ne 0)
    {
        Write-Error "Composer dev install failed before PHP-Scoper"
        if ($devComposerResult)
        {
            Write-Host ($devComposerResult -join [Environment]::NewLine) -ForegroundColor Gray
        }
        exit 1
    }

    $scoperPath = "vendor\bin\php-scoper.bat"
    if (-not (Test-Path $scoperPath))
    {
        $scoperPath = "vendor\bin\php-scoper"
    }

    if (Test-Path $scoperPath)
    {
        $scoperResult = & $scoperPath add-prefix --output-dir=$BUILD_DIR --force 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            Write-Error "PHP-Scoper failed"
            Write-Host $scoperResult -ForegroundColor Gray
            exit 1
        }
        Write-Success "PHP-Scoper completed"
    }
    else
    {
        Write-Error "PHP-Scoper not found in vendor/bin"
        exit 1
    }
}
else
{
    Write-Step "Skipping PHP-Scoper (dev build)..."
    New-Item -Path $BUILD_DIR -ItemType Directory -Force | Out-Null

    # Copy source files
    $sourceDirs = @("app", "bootstrap", "config", "database", "includes", "resources", "routes")
    foreach ($dir in $sourceDirs)
    {
        if (Test-Path $dir)
        {
            Copy-Item -Path $dir -Destination "$BUILD_DIR\$dir" -Recurse -Force
        }
    }

    # Copy vendor
    if (Test-Path "vendor")
    {
        Copy-Item -Path "vendor" -Destination "$BUILD_DIR\vendor" -Recurse -Force
    }

    Write-Success "Files copied to build directory"
}

# Step 5: Copy essential files to build (using intelligent detection)
Write-Step "Detecting and copying build files..."

$buildItems = Get-IncludedItems

Write-Host "  Directories: $( $buildItems.Dirs -join ', ' )" -ForegroundColor Gray
Write-Host "  Files: $( $buildItems.Files -join ', ' )" -ForegroundColor Gray

# Copy included files
foreach ($file in $buildItems.Files)
{
    if (Test-Path $file)
    {
        Copy-Item -Path $file -Destination "$BUILD_DIR\" -Force
    }
}

# Copy included directories (that aren't already scoped/copied)
foreach ($dir in $buildItems.Dirs)
{
    if ((Test-Path $dir) -and -not (Test-Path "$BUILD_DIR\$dir"))
    {
        Copy-Item -Path $dir -Destination "$BUILD_DIR\$dir" -Recurse -Force
    }
}

Write-Success "Build files copied"

Update-BuildVersion

Copy-FrontendDist

# Step 6: Generate optimized production autoload in build directory
Write-Step "Generating optimized production autoload in build directory..."
Push-Location $BUILD_DIR
Start-Sleep -Seconds 2

if (Test-Path "composer.lock")
{
    $autoloadResult = & cmd.exe /d /c "composer.bat install --no-dev --prefer-dist --no-progress --no-interaction --no-ansi --optimize-autoloader --classmap-authoritative 2>&1"
}
else
{
    $autoloadResult = & cmd.exe /d /c "composer.bat dump-autoload --no-dev --no-ansi --optimize --classmap-authoritative 2>&1"
}

$autoloadExitCode = $LASTEXITCODE

Pop-Location

if ($autoloadExitCode -eq 0)
{
    Write-Success "Production autoload generated in build"
}
else
{
    Write-Warning "Composer autoload issue in build"
    if ($autoloadResult)
    {
        Write-Host ($autoloadResult -join [Environment]::NewLine) -ForegroundColor Gray
    }
}

# Step 7: Remove development files from build
Write-Step "Removing development files..."

$devFiles = @(
    "$BUILD_DIR\.git",
    "$BUILD_DIR\.github",
    "$BUILD_DIR\.gitignore",
    "$BUILD_DIR\.gitattributes",
    "$BUILD_DIR\.plugin-config.json",
    "$BUILD_DIR\tests",
    "$BUILD_DIR\phpunit.xml",
    "$BUILD_DIR\phpstan.neon",
    "$BUILD_DIR\phpcs.xml.dist",
    "$BUILD_DIR\scoper.inc.php",
    "$BUILD_DIR\init-plugin.ps1",
    "$BUILD_DIR\init-plugin.sh",
    "$BUILD_DIR\build.ps1",
    "$BUILD_DIR\build.sh",
    "$BUILD_DIR\Makefile",
    "$BUILD_DIR\CONTRIBUTING.md",
    "$BUILD_DIR\SECURITY.md",
    "$BUILD_DIR\CHANGELOG.md",
    "$BUILD_DIR\composer.lock",
    "$BUILD_DIR\composer.json"
)

foreach ($file in $devFiles)
{
    if (Test-Path $file)
    {
        Remove-Item -Path $file -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Remove-FrontendSourceFiles

Write-Success "Development files removed"

# Step 8: Create ZIP
Write-Step "Creating distributable ZIP..."

New-Item -Path $DIST_DIR -ItemType Directory -Force | Out-Null

$zipPath = "$DIST_DIR\$PLUGIN_SLUG-$Version.zip"

# Use .NET compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $zipPath)
{
    Remove-Item $zipPath -Force
}

# Create temp directory with plugin folder structure
$tempDir = "$DIST_DIR\temp"
$tempPluginDir = "$tempDir\$PLUGIN_SLUG"
New-Item -Path $tempPluginDir -ItemType Directory -Force | Out-Null
Copy-Item -Path "$BUILD_DIR\*" -Destination $tempPluginDir -Recurse -Force

$integrityHash = Get-ReleaseIntegrityHash -PluginDir $tempPluginDir

# Create ZIP
[System.IO.Compression.ZipFile]::CreateFromDirectory(
        $tempDir,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
)

Remove-Item -Path $tempDir -Recurse -Force

# Clean up build directory (keep only dist with ZIP)
if (Test-Path $BUILD_DIR)
{
    Remove-Item -Path $BUILD_DIR -Recurse -Force
}

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB, 2)
$zipHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Invoke-IntegrityUpdate -IntegrityHash $integrityHash -PackageHash $zipHash
Remove-LooseDistArtifacts
Write-Success "Created: $zipPath ($zipSize KB)"

# ============================================================================
# Summary
# ============================================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Plugin:     $PLUGIN_NAME" -ForegroundColor Gray
Write-Host "Version:    $Version" -ForegroundColor Gray
Write-Host "Output:     $zipPath" -ForegroundColor Gray
Write-Host "Size:       $zipSize KB" -ForegroundColor Gray
if ($integrityHash)
{
    Write-Host "Integrity:  $integrityHash" -ForegroundColor Gray
}
Write-Host "SHA256:     $zipHash" -ForegroundColor Gray
Write-Host ""

if (-not $SkipQA)
{
    Write-Host "QA Checks:  Passed (phpcbf, phpstan)" -ForegroundColor Gray
}
if (-not $SkipScoper)
{
    Write-Host "Scoped:     Yes (namespace isolation)" -ForegroundColor Gray
}
Write-Host "License DB: $( if ($script:IntegrityUpdatePerformed)
{
    'Updated automatically'
}
else
{
    'Not updated'
} )" -ForegroundColor Gray

Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Test installation on staging site" -ForegroundColor Gray
Write-Host "  2. Upload to WordPress or distribute" -ForegroundColor Gray
Write-Host ""
