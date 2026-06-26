#!/bin/bash
# ============================================================================
# WPZylos Scaffold - Build Script
# ============================================================================
# Creates a production-ready distributable ZIP with PHP-Scoper isolation.
# Reads configuration from .plugin-config.json (created by init-plugin.sh).
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
# Location: .scripts/build.sh
# Called by: ../wpzylos
# ============================================================================

set -e

# ============================================================================
# Change to project root (parent of .scripts)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

# ============================================================================
# Configuration
# ============================================================================

BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
CONFIG_FILE=".plugin-config.json"
SKIP_QA=false
SKIP_SCOPER=false
CLEAN_ONLY=false
VERSION=""
PHPSTAN_MEMORY_LIMIT="1G"
INTEGRITY_UPDATE_URL="${LICENSE_INTEGRITY_UPDATE_URL:-https://license-verification.test/api/v1/plugin/integrity}"
INTEGRITY_UPDATE_TOKEN="${LICENSE_INTEGRITY_UPDATE_TOKEN:-}"
INTEGRITY_UPDATE_PERFORMED=false

config_value() {
    local path="$1"
    local separator="${2:-,}"
    if command -v jq &> /dev/null; then
        jq -r --arg path "$path" --arg separator "$separator" '
            getpath($path | split(".")) // empty |
            if type == "array" then join($separator) else tostring end
        ' "$CONFIG_FILE"
    elif command -v php &> /dev/null; then
        php -r '
            $value = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
            foreach (explode(".", $argv[2]) as $key) {
                $value = is_array($value) && array_key_exists($key, $value) ? $value[$key] : null;
            }
            echo is_array($value) ? implode($argv[3], $value) : (string) ($value ?? "");
        ' "$CONFIG_FILE" "$path" "$separator"
    else
        echo -e "${RED}Error: jq or php is required to read $CONFIG_FILE safely.${NC}" >&2
        return 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-qa) SKIP_QA=true; shift ;;
        --skip-scoper) SKIP_SCOPER=true; shift ;;
        --clean) CLEAN_ONLY=true; shift ;;
        --version) VERSION="$2"; shift 2 ;;
        --phpstan-memory-limit) PHPSTAN_MEMORY_LIMIT="$2"; shift 2 ;;
        --integrity-update-url) INTEGRITY_UPDATE_URL="$2"; shift 2 ;;
        --integrity-update-token) INTEGRITY_UPDATE_TOKEN="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Load plugin config
if [[ -f "$CONFIG_FILE" ]]; then
    PLUGIN_SLUG=$(config_value plugin.slug)
    PLUGIN_NAME=$(config_value plugin.name)
    MAIN_FILE=$(config_value plugin.mainFile)
    
    if [[ -z "$VERSION" ]]; then
        VERSION=$(config_value plugin.version)
    fi

    if [[ -z "$INTEGRITY_UPDATE_TOKEN" ]]; then
        INTEGRITY_UPDATE_TOKEN=$(config_value build.integrityUpdateToken)
    fi

    if [[ "$INTEGRITY_UPDATE_URL" == "https://license-verification.test/api/v1/plugin/integrity" ]]; then
        CONFIG_INTEGRITY_UPDATE_URL=$(config_value build.integrityUpdateUrl)
        if [[ -n "$CONFIG_INTEGRITY_UPDATE_URL" ]]; then
            INTEGRITY_UPDATE_URL="$CONFIG_INTEGRITY_UPDATE_URL"
        fi
    fi
else
    echo -e "${YELLOW}Warning: .plugin-config.json not found. Using auto-detection.${NC}"
    echo -e "${YELLOW}Run init-plugin.sh first for best results.${NC}"
    echo ""
    
    MAIN_FILE=$(find . -maxdepth 1 -name "*.php" -type f ! -name "uninstall.php" ! -name "scoper.inc.php" ! -name "index.php" | head -1)
    if [[ -z "$MAIN_FILE" ]]; then
        echo -e "${RED}Error: Could not find main plugin file.${NC}"
        exit 1
    fi
    
    MAIN_FILE=$(basename "$MAIN_FILE")
    PLUGIN_SLUG="${MAIN_FILE%.php}"
    PLUGIN_NAME="$PLUGIN_SLUG"
    
    if [[ -z "$VERSION" ]]; then
        VERSION=$(grep -oP "Version:\s*\K[0-9.]+" "$MAIN_FILE" 2>/dev/null || echo "1.0.0")
    fi
fi

if [[ -z "$VERSION" ]]; then
    VERSION="1.0.0"
fi

# ============================================================================
# Intelligent Version Suggestion
# ============================================================================

get_suggested_version() {
    local plugin_slug="$1"
    
    # Check for existing ZIPs in dist/
    if [[ -d "$DIST_DIR" ]]; then
        local latest_zip=$(ls -1 "$DIST_DIR"/${plugin_slug}-*.zip 2>/dev/null | sort -V | tail -1)
        
        if [[ -n "$latest_zip" ]]; then
            # Extract version from ZIP filename
            local zip_name=$(basename "$latest_zip")
            if [[ "$zip_name" =~ ${plugin_slug}-([0-9]+)\.([0-9]+)\.([0-9]+)\.zip ]]; then
                local major="${BASH_REMATCH[1]}"
                local minor="${BASH_REMATCH[2]}"
                local patch="${BASH_REMATCH[3]}"
                
                # Suggest next patch version
                echo "$major.$minor.$((patch + 1))"
                return
            fi
        fi
    fi
    
    # No existing ZIPs, suggest 1.0.0
    echo "1.0.0"
}

# Only prompt if version wasn't passed via command line
VERSION_FROM_ARG=false
for arg in "$@"; do
    if [[ "$arg" == "--version" ]]; then
        VERSION_FROM_ARG=true
        break
    fi
done

if [[ "$VERSION_FROM_ARG" == false ]]; then
    SUGGESTED_VERSION=$(get_suggested_version "$PLUGIN_SLUG")
    
    # Check if ZIP already exists for current version
    CURRENT_ZIP_PATH="$DIST_DIR/$PLUGIN_SLUG-$VERSION.zip"
    if [[ -f "$CURRENT_ZIP_PATH" ]]; then
        echo ""
        echo -e "  ${YELLOW}ZIP already exists for version $VERSION${NC}"
        echo -e "  ${WHITE}Suggested next version: ${CYAN}$SUGGESTED_VERSION${NC}"
        echo ""
        read -r -p "  Version [$SUGGESTED_VERSION]: " USER_VERSION
        if [[ -z "$USER_VERSION" ]]; then
            VERSION="$SUGGESTED_VERSION"
        else
            VERSION="$USER_VERSION"
        fi
    elif [[ "$VERSION" == "1.0.0" && "$SUGGESTED_VERSION" != "1.0.0" ]]; then
        # Config has 1.0.0 but we have existing builds
        echo ""
        echo -e "  ${WHITE}Existing builds found. Suggested version: ${CYAN}$SUGGESTED_VERSION${NC}"
        echo ""
        read -r -p "  Version [$SUGGESTED_VERSION]: " USER_VERSION
        if [[ -z "$USER_VERSION" ]]; then
            VERSION="$SUGGESTED_VERSION"
        else
            VERSION="$USER_VERSION"
        fi
    fi
fi

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}  __      __  _____   ______ __     __ _       ____   _____ ${NC}"
    echo -e "${BLUE}  \\ \\    / / |  __ \\ |___  / \\ \\   / /| |     / __ \\ / ____|${NC}"
    echo -e "${BLUE}   \\ \\  / /  | |__) |   / /   \\ \\_/ / | |    | |  | | (___  ${NC}"
    echo -e "${BLUE}    \\ \\/ /   |  ___/   / /     \\   /  | |    | |  | | \\___ \\ ${NC}"
    echo -e "${BLUE}     \\  /    | |      / /__     | |   | |____| |__| | ____) |${NC}"
    echo -e "${BLUE}      \\/     |_|     /_____|    |_|   |______| \\____/ |_____/ ${NC}"
    echo ""
    echo -e "${GRAY}  $1${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}[*] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# ============================================================================
# Intelligent Build Config Functions
# ============================================================================

# Known items that should always be excluded from build
ALWAYS_EXCLUDE=".git .github .scripts .vite .gitignore .gitattributes vendor tests docs node_modules phpstan-stubs composer.lock phpstan.neon phpstan.neon.dist phpunit.xml scoper.inc.php scaffold.ps1 scaffold.sh CONTRIBUTING.md SECURITY.md CHANGELOG.md .plugin-config.json build dist"

# Base structure directories that should be auto-included
BASE_STRUCTURE_DIRS="app bootstrap config database resources routes"

# Essential files that should be auto-included
ESSENTIAL_FILES="uninstall.php readme.txt LICENSE composer.json"

get_included_items() {
    local needs_save=false
    
    # Initialize arrays
    INCLUDE_DIRS=""
    INCLUDE_FILES=""
    PROMPTED_ITEMS=""
    
    # Load existing build config from .plugin-config.json
    if [[ -f "$CONFIG_FILE" ]]; then
        INCLUDE_DIRS=$(config_value build.includeDirs " ")
        INCLUDE_FILES=$(config_value build.includeFiles " ")
        PROMPTED_ITEMS=$(config_value build.promptedItems " ")
    fi
    
    # Scan root directory
    for item in */ ; do
        item="${item%/}"  # Remove trailing slash
        [[ -z "$item" || "$item" == "*" ]] && continue
        
        # Skip excluded items
        if [[ " $ALWAYS_EXCLUDE " == *" $item "* ]]; then
            continue
        fi
        
        # Auto-include base structure
        if [[ " $BASE_STRUCTURE_DIRS " == *" $item "* ]]; then
            if [[ " $INCLUDE_DIRS " != *" $item "* ]]; then
                INCLUDE_DIRS="$INCLUDE_DIRS $item"
                needs_save=true
            fi
        # Prompt for unknown directories
        elif [[ " $PROMPTED_ITEMS " != *" $item "* ]]; then
            echo ""
            echo -e "  ${WHITE}Unknown directory found: ${CYAN}$item/${NC}"
            read -r -p "  Include in build? [Y/n]: " answer
            
            PROMPTED_ITEMS="$PROMPTED_ITEMS $item"
            if [[ "$answer" != "n" && "$answer" != "N" ]]; then
                INCLUDE_DIRS="$INCLUDE_DIRS $item"
            fi
            needs_save=true
        fi
    done
    
    # Process PHP files at root
    for file in *.php; do
        [[ -f "$file" ]] || continue
        
        # Skip known files
        if [[ "$file" == "$MAIN_FILE" || "$file" == "uninstall.php" || "$file" == "scoper.inc.php" || "$file" == "index.php" ]]; then
            continue
        fi
        
        # Skip excluded items
        if [[ " $ALWAYS_EXCLUDE " == *" $file "* ]]; then
            continue
        fi
        
        # Prompt for unknown PHP files
        if [[ " $PROMPTED_ITEMS " != *" $file "* ]]; then
            echo ""
            echo -e "  ${WHITE}Unknown PHP file found: ${CYAN}$file${NC}"
            read -r -p "  Include in build? [Y/n]: " answer
            
            PROMPTED_ITEMS="$PROMPTED_ITEMS $file"
            if [[ "$answer" != "n" && "$answer" != "N" ]]; then
                INCLUDE_FILES="$INCLUDE_FILES $file"
            fi
            needs_save=true
        fi
    done
    
    # Add essential files
    for file in $ESSENTIAL_FILES; do
        if [[ -f "$file" && " $INCLUDE_FILES " != *" $file "* ]]; then
            INCLUDE_FILES="$INCLUDE_FILES $file"
            needs_save=true
        fi
    done
    
    # Always include main plugin file
    if [[ " $INCLUDE_FILES " != *" $MAIN_FILE "* ]]; then
        INCLUDE_FILES="$INCLUDE_FILES $MAIN_FILE"
        needs_save=true
    fi
    
    # Normalize (trim and unique)
    INCLUDE_DIRS=$(echo $INCLUDE_DIRS | tr ' ' '\n' | sort -u | xargs)
    INCLUDE_FILES=$(echo $INCLUDE_FILES | tr ' ' '\n' | sort -u | xargs)
    PROMPTED_ITEMS=$(echo $PROMPTED_ITEMS | tr ' ' '\n' | sort -u | xargs)
    
    # Save config if changed
    if [[ "$needs_save" == true && -f "$CONFIG_FILE" ]]; then
        save_build_config
        echo ""
        echo -e "  ${GRAY}Build preferences saved to .plugin-config.json${NC}"
    fi
}

save_build_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi
    
    # Convert space-separated to JSON array format
    local dirs_json=$(echo $INCLUDE_DIRS | tr ' ' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
    local files_json=$(echo $INCLUDE_FILES | tr ' ' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
    local prompted_json=$(echo $PROMPTED_ITEMS | tr ' ' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
    
    # Read existing config and add/update build section
    local temp_file=$(mktemp)
    
    # Merge only managed arrays so integrity and future/custom settings survive.
    if command -v jq &> /dev/null; then
        jq --arg dirs "[$dirs_json]" --arg files "[$files_json]" --arg prompted "[$prompted_json]" \
           '.build = ((.build // {}) + {includeDirs: ($dirs | fromjson), includeFiles: ($files | fromjson), promptedItems: ($prompted | fromjson)})' \
           "$CONFIG_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$CONFIG_FILE"
    elif command -v php &> /dev/null; then
        php -r '
            $path = $argv[1];
            $config = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
            $config["build"] = array_merge($config["build"] ?? [], [
                "includeDirs" => json_decode($argv[2], true, 512, JSON_THROW_ON_ERROR),
                "includeFiles" => json_decode($argv[3], true, 512, JSON_THROW_ON_ERROR),
                "promptedItems" => json_decode($argv[4], true, 512, JSON_THROW_ON_ERROR),
            ]);
            file_put_contents($path, json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
        ' "$CONFIG_FILE" "[$dirs_json]" "[$files_json]" "[$prompted_json]"
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
        echo -e "${RED}Error: jq or php is required to safely update $CONFIG_FILE.${NC}"
        return 1
    fi
}

clean_build() {
    print_step "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    # Note: dist/ is preserved to keep previous ZIP builds
    print_success "Cleaned build directory"
}

run_phpcbf() {
    print_step "Running PHP Code Beautifier (phpcbf --standard=PSR12)..."
    
    if [[ -f "vendor/bin/phpcbf" ]]; then
        set +e
        vendor/bin/phpcbf --standard=PSR12 app 2>&1
        RESULT=$?
        set -e
        
        if [[ $RESULT -eq 0 ]]; then
            print_success "No code style issues found"
        elif [[ $RESULT -eq 1 ]]; then
            print_success "Code style issues auto-fixed"
        else
            print_warning "phpcbf returned exit code $RESULT"
        fi
    else
        print_warning "phpcbf not found. Skipping code style fix."
    fi
}

run_phpstan() {
    print_step "Running static analysis (phpstan analyze --memory-limit=$PHPSTAN_MEMORY_LIMIT)..."
    
    if [[ -f "vendor/bin/phpstan" ]]; then
        set +e
        vendor/bin/phpstan analyze app --no-progress "--memory-limit=$PHPSTAN_MEMORY_LIMIT" 2>&1
        RESULT=$?
        set -e
        
        if [[ $RESULT -eq 0 ]]; then
            print_success "Static analysis passed"
        else
            print_error "Static analysis found issues"
            read -p "Continue build anyway? [y/N]: " CONTINUE
            if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
                exit 1
            fi
        fi
    else
        print_warning "phpstan not found. Skipping static analysis."
    fi
}

copy_frontend_dist() {
    if [[ ! -d "$DIST_DIR" ]]; then
        return
    fi

    print_step "Copying frontend production assets..."

    local target_dir="$BUILD_DIR/dist"
    mkdir -p "$target_dir"

    shopt -s dotglob nullglob
    for item in "$DIST_DIR"/*; do
        local name
        name="$(basename "$item")"

        if [[ "$name" == "temp" || "$name" == *.zip ]]; then
            continue
        fi

        cp -r "$item" "$target_dir/"
    done
    shopt -u dotglob nullglob

    print_success "Frontend assets copied"
}

remove_frontend_source_files() {
    if [[ ! -f "$BUILD_DIR/dist/.vite/manifest.json" ]]; then
        return
    fi

    print_step "Removing frontend source files..."
    rm -rf \
        "$BUILD_DIR/resources/js" \
        "$BUILD_DIR/resources/css" \
        "$BUILD_DIR/resources/scss" \
        "$BUILD_DIR/resources/sass" \
        "$BUILD_DIR/resources/ts" \
        "$BUILD_DIR/resources/tsx" \
        "$BUILD_DIR/resources/vue" \
        "$BUILD_DIR/resources/react"
    print_success "Frontend source files removed"
}

update_build_version() {
    local main_path="$BUILD_DIR/$MAIN_FILE"
    if [[ ! -f "$main_path" ]]; then
        print_error "Main plugin file is missing from build: $MAIN_FILE"
        exit 1
    fi

    php -r '
        $path = $argv[1];
        $version = $argv[2];
        $content = file_get_contents($path);
        $content = preg_replace_callback(
            "/^(\\s*\\*\\s*Version:\\s*)[^\\r\\n]+/m",
            static fn (array $match): string => $match[1].$version,
            $content
        );
        $content = preg_replace_callback(
            "/(\x27version\x27\\s*=>\\s*\x27)[^\x27]+(\x27)/",
            static fn (array $match): string => $match[1].$version.$match[2],
            $content,
            1
        );
        file_put_contents($path, $content);

        $readme = $argv[3];
        if (is_file($readme)) {
            $content = file_get_contents($readme);
            $content = preg_replace_callback(
                "/^(Stable tag:\\s*)[^\\r\\n]+/m",
                static fn (array $match): string => $match[1].$version,
                $content
            );
            file_put_contents($readme, $content);
        }
    ' "$main_path" "$VERSION" "$BUILD_DIR/readme.txt"

    print_success "Packaged plugin version set to $VERSION"
}

remove_loose_dist_artifacts() {
    if [[ ! -d "$DIST_DIR" ]]; then
        return
    fi

    print_step "Cleaning loose dist assets..."
    find "$DIST_DIR" -mindepth 1 ! -name "*.zip" -exec rm -rf {} +
    print_success "Loose dist assets removed"
}

get_release_integrity_hash() {
    local plugin_dir="$1"
    local temp_file
    temp_file="$(mktemp)"

    cat > "$temp_file" <<'PHP'
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
PHP

    local hash
    hash="$(php "$temp_file" "$plugin_dir" "$PLUGIN_SLUG" "$VERSION" "$MAIN_FILE" 2>/dev/null || true)"
    rm -f "$temp_file"

    if [[ "$hash" =~ ^[a-f0-9]{64}$ ]]; then
        echo "$hash"
    fi
}

get_file_sha256() {
    local file="$1"

    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | awk '{print tolower($1)}'
        return
    fi

    if command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | awk '{print tolower($1)}'
        return
    fi

    if command -v powershell.exe &> /dev/null; then
        local ps_file="$file"
        if command -v cygpath &> /dev/null; then
            ps_file="$(cygpath -w "$file")"
        fi

        powershell.exe -NoProfile -Command "(Get-FileHash -Path '$ps_file' -Algorithm SHA256).Hash.ToLowerInvariant()" 2>/dev/null | tr -d '\r'
    fi
}

update_license_server_integrity() {
    local integrity_hash="$1"
    local package_hash="$2"

    if [[ -z "$INTEGRITY_UPDATE_URL" ]]; then
        print_warning "Integrity update URL is not configured. Skipping license server update."
        return
    fi

    if [[ -z "$INTEGRITY_UPDATE_TOKEN" ]]; then
        print_warning "Integrity update token is not configured. Skipping license server update."
        return
    fi

    if [[ -z "$integrity_hash" ]]; then
        print_error "Integrity hash is empty. Cannot update license server."
        exit 1
    fi

    print_step "Updating license server integrity hash..."

    local payload
    payload=$(php -r 'echo json_encode([
        "product_slug" => $argv[1],
        "integrity_hash" => $argv[2],
        "update_token" => $argv[3],
        "package_sha256" => $argv[4],
        "version" => $argv[5],
        "integrity_notes" => "Updated by WPZylos build",
    ]);' "$PLUGIN_SLUG" "$integrity_hash" "$INTEGRITY_UPDATE_TOKEN" "$package_hash" "$VERSION")

    if command -v curl &> /dev/null; then
        local response
        response=$(curl -ksS -X POST "$INTEGRITY_UPDATE_URL" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            --data "$payload")

        if ! php -r '$data=json_decode(stream_get_contents(STDIN), true); exit(is_array($data) && !empty($data["success"]) ? 0 : 1);' <<< "$response"; then
            print_error "License server integrity update failed"
            echo "$response"
            exit 1
        fi

        print_success "License server integrity hash updated"
        INTEGRITY_UPDATE_PERFORMED=true
        return
    fi

    print_error "curl is required to update license server integrity from build.sh"
    exit 1
}

# ============================================================================
# Main Build Process
# ============================================================================

print_header "WPZylos Build - $PLUGIN_SLUG v$VERSION"

# Clean only mode
if [[ "$CLEAN_ONLY" == true ]]; then
    clean_build
    exit 0
fi

# Step 1: Clean
clean_build

# Step 2: Run QA (unless skipped)
if [[ "$SKIP_QA" == false ]]; then
    print_step "Ensuring dev dependencies are installed..."
    sleep 2; if ! composer install --no-interaction --no-progress 2>&1; then
        print_error "Composer dev install failed"
        exit 1
    fi
    print_success "Dependencies ready"
    
    run_phpcbf
    run_phpstan
else
    print_step "Skipping QA checks..."
fi

# Step 3: Install production dependencies
print_step "Installing production dependencies..."
sleep 2; if ! composer install --no-dev --prefer-dist --no-progress --no-interaction --optimize-autoloader --classmap-authoritative 2>&1; then
    print_error "Composer install failed"
    exit 1
fi
print_success "Production dependencies installed"

# Step: Build frontend assets
echo "Building frontend assets..."
if [ -f "package.json" ]; then
    npm install --silent
    npm run build
    if [ $? -ne 0 ]; then
        echo "Frontend build failed!"
        exit 1
    fi
    echo "Frontend assets built."
fi

# Step 4: Run PHP-Scoper (unless skipped)
if [[ "$SKIP_SCOPER" == false ]]; then
    print_step "Running PHP-Scoper..."
    
    # Re-install dev deps for scoper
    sleep 2; if ! composer install --no-interaction --no-progress 2>&1; then
        print_error "Composer dev install failed before PHP-Scoper"
        exit 1
    fi
    
    if [[ -f "vendor/bin/php-scoper" ]]; then
        if ! vendor/bin/php-scoper add-prefix --output-dir="$BUILD_DIR" --force 2>&1; then
            print_error "PHP-Scoper failed"
            exit 1
        fi
        print_success "PHP-Scoper completed"
    else
        print_error "PHP-Scoper not found in vendor/bin"
        exit 1
    fi
else
    print_step "Skipping PHP-Scoper (dev build)..."
    mkdir -p "$BUILD_DIR"
    
    for dir in app bootstrap config database resources routes vendor; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "$BUILD_DIR/"
        fi
    done
    
    print_success "Files copied to build directory"
fi

# Step 5: Copy essential files (using intelligent detection)
print_step "Detecting and copying build files..."

get_included_items

echo -e "  ${GRAY}Directories: $INCLUDE_DIRS${NC}"
echo -e "  ${GRAY}Files: $INCLUDE_FILES${NC}"

# Copy included files
for file in $INCLUDE_FILES; do
    if [[ -f "$file" ]]; then
        cp "$file" "$BUILD_DIR/"
    fi
done

# Copy included directories (that aren't already scoped/copied)
for dir in $INCLUDE_DIRS; do
    if [[ -d "$dir" ]] && [[ ! -d "$BUILD_DIR/$dir" ]]; then
        cp -r "$dir" "$BUILD_DIR/"
    fi
done

print_success "Build files copied"

update_build_version

copy_frontend_dist

# Step 6: Install production dependencies in build directory
print_step "Installing production dependencies in build directory..."
(
    cd "$BUILD_DIR" 2>/dev/null || exit 1
    sleep 2; if composer install --no-dev --prefer-dist --no-progress --no-interaction --optimize-autoloader --classmap-authoritative 2>&1; then
        exit 0
    else
        exit 1
    fi
)
if [[ $? -eq 0 ]]; then
    print_success "Production dependencies installed in build"
else
    print_warning "Composer install issue in build (may still work)"
fi

# Step 7: Remove development files
print_step "Removing development files..."

rm -rf \
    "$BUILD_DIR/.git" \
    "$BUILD_DIR/.github" \
    "$BUILD_DIR/.gitignore" \
    "$BUILD_DIR/.gitattributes" \
    "$BUILD_DIR/.plugin-config.json" \
    "$BUILD_DIR/tests" \
    "$BUILD_DIR/phpunit.xml" \
    "$BUILD_DIR/phpstan.neon" \
    "$BUILD_DIR/phpcs.xml.dist" \
    "$BUILD_DIR/scoper.inc.php" \
    "$BUILD_DIR/init-plugin.ps1" \
    "$BUILD_DIR/init-plugin.sh" \
    "$BUILD_DIR/build.ps1" \
    "$BUILD_DIR/build.sh" \
    "$BUILD_DIR/Makefile" \
    "$BUILD_DIR/CONTRIBUTING.md" \
    "$BUILD_DIR/SECURITY.md" \
    "$BUILD_DIR/CHANGELOG.md" \
    "$BUILD_DIR/composer.lock" \
    "$BUILD_DIR/composer.json" \
    2>/dev/null || true

remove_frontend_source_files

print_success "Development files removed"

# Step 8: Create ZIP
print_step "Creating distributable ZIP..."

mkdir -p "$DIST_DIR"

ZIP_PATH="$DIST_DIR/$PLUGIN_SLUG-$VERSION.zip"

# Create temp directory with plugin folder
TEMP_DIR="$DIST_DIR/temp"
mkdir -p "$TEMP_DIR/$PLUGIN_SLUG"
cp -r "$BUILD_DIR"/* "$TEMP_DIR/$PLUGIN_SLUG/"

INTEGRITY_HASH="$(get_release_integrity_hash "$TEMP_DIR/$PLUGIN_SLUG")"

# Create ZIP - check for available zip tools
ORIG_DIR="$(pwd)"
cd "$TEMP_DIR" 2>/dev/null

# Try native zip first, then 7z, then PowerShell as fallback
if command -v zip &> /dev/null; then
    zip -r "../$PLUGIN_SLUG-$VERSION.zip" "$PLUGIN_SLUG" -q
elif command -v 7z &> /dev/null; then
    7z a -tzip "../$PLUGIN_SLUG-$VERSION.zip" "$PLUGIN_SLUG" -bso0 -bsp0
else
    # PowerShell fallback for Windows Git Bash
    if command -v powershell.exe &> /dev/null; then
        powershell.exe -Command "Compress-Archive -Path '$PLUGIN_SLUG' -DestinationPath '../$PLUGIN_SLUG-$VERSION.zip' -Force"
    else
        print_error "No zip tool found. Install zip, 7z, or run from PowerShell."
        exit 1
    fi
fi

cd "$ORIG_DIR" 2>/dev/null

rm -rf "$TEMP_DIR"

# Clean up build directory (keep only dist with ZIP)
rm -rf "$BUILD_DIR"

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
ZIP_HASH="$(get_file_sha256 "$ZIP_PATH")"
update_license_server_integrity "$INTEGRITY_HASH" "$ZIP_HASH"
remove_loose_dist_artifacts
print_success "Created: $ZIP_PATH ($ZIP_SIZE)"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${GRAY}Plugin:     $PLUGIN_NAME${NC}"
echo -e "${GRAY}Version:    $VERSION${NC}"
echo -e "${GRAY}Output:     $ZIP_PATH${NC}"
echo -e "${GRAY}Size:       $ZIP_SIZE${NC}"
if [[ -n "$INTEGRITY_HASH" ]]; then
    echo -e "${GRAY}Integrity:  $INTEGRITY_HASH${NC}"
fi
if [[ -n "$ZIP_HASH" ]]; then
    echo -e "${GRAY}SHA256:     $ZIP_HASH${NC}"
fi
echo ""

if [[ "$SKIP_QA" == false ]]; then
    echo -e "${GRAY}QA Checks:  Passed (phpcbf, phpstan)${NC}"
fi
if [[ "$SKIP_SCOPER" == false ]]; then
    echo -e "${GRAY}Scoped:     Yes (namespace isolation)${NC}"
fi
if [[ "$INTEGRITY_UPDATE_PERFORMED" == true ]]; then
    echo -e "${GRAY}License DB: Updated automatically${NC}"
else
    echo -e "${GRAY}License DB: Not updated${NC}"
fi

echo ""
echo "Next steps:"
echo -e "${GRAY}  1. Test installation on staging site${NC}"
echo -e "${GRAY}  2. Upload to WordPress or distribute${NC}"
echo ""
