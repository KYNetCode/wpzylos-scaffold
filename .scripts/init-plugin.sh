#!/bin/bash
# ============================================================================
# WPZylos Scaffold - Plugin Initializer (Intelligent)
# ============================================================================
# Handles all scenarios:
# - Fresh install (my-plugin.php exists)
# - Re-configuration (update existing config)
# - Config deleted (detect from renamed files)
# - Partial updates (only change specific values)
#
# Location: .scripts/init-plugin.sh
# Called by: ../scaffold.sh
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
GRAY='\033[0;37m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}  ██╗    ██╗██████╗ ███████╗██╗   ██╗██╗      ██████╗ ███████╗${NC}"
    echo -e "${BLUE}  ██║    ██║██╔══██╗╚══███╔╝╚██╗ ██╔╝██║     ██╔═══██╗██╔════╝${NC}"
    echo -e "${BLUE}  ██║ █╗ ██║██████╔╝  ███╔╝  ╚████╔╝ ██║     ██║   ██║███████╗${NC}"
    echo -e "${BLUE}  ██║███╗██║██╔═══╝  ███╔╝    ╚██╔╝  ██║     ██║   ██║╚════██║${NC}"
    echo -e "${BLUE}  ╚███╔███╔╝██║     ███████╗   ██║   ███████╗╚██████╔╝███████║${NC}"
    echo -e "${BLUE}   ╚══╝╚══╝ ╚═╝     ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚══════╝${NC}"
    echo ""
    echo -e "  ${GRAY}Plugin Initializer${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_step() {
    echo -ne "${YELLOW}[$1/$2] $3... ${NC}"
}

print_done() {
    echo -e "${GREEN}Done${NC}"
}

print_skip() {
    echo -e "${GRAY}Skipped${NC}"
}

# Convert "My Awesome Plugin" to "my-awesome-plugin"
to_slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/-\+/-/g' | sed 's/^-\|-$//g'
}

# Convert "my-awesome-plugin" to "MyAwesomePlugin"
to_namespace() {
    echo "$1" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1' | tr -d ' '
}

# Convert "my-awesome-plugin" to "my_awesome_plugin"
to_scoper_prefix() {
    echo "$1" | tr '-' '_'
}

# Convert "my-awesome-plugin" to "myawesomeplugin_"
to_db_prefix() {
    echo "$1" | tr -d '-' | sed 's/$/_/'
}

# Convert "My Awesome Plugin" to "map-" (first letter of each word)
convert_to_css_prefix() {
    local name="$1"
    local cleaned=$(echo "$name" | sed 's/[^a-zA-Z ]//g' | xargs)
    local prefix=""
    for word in $cleaned; do
        prefix="${prefix}${word:0:1}"
    done
    echo "$(echo "$prefix" | tr '[:upper:]' '[:lower:]')-"
}

# Convert "Your Name" to "yourname"
to_vendor() {
    echo "$1" | tr -d ' ' | tr '[:upper:]' '[:lower:]'
}

# Read with default value, showing current if exists
# Uses -r to preserve backslashes, -e for readline support
read_with_default() {
    local prompt="$1"
    local default="$2"
    local input
    # -r: don't interpret backslashes
    # -e: use readline for editing (handles arrow keys properly)
    read -r -e -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

# Read a comma-separated list. Enter <none> to clear it.
read_list_with_default() {
    local prompt="$1"
    local default="$2"
    local input
    read -r -e -p "$prompt [$default]: " input
    if [[ -z "$input" ]]; then
        echo "$default"
    elif [[ "$input" == "<none>" ]]; then
        echo ""
    else
        echo "$input"
    fi
}

# Normalize namespace: convert any number of consecutive backslashes to single
# Handles: \ , \\ , \\\ all become single \
normalize_namespace() {
    local ns="$1"
    # Replace 3+ backslashes with single, then 2 with single
    # This handles \\\ -> \ and \\ -> \ while preserving single \
    printf '%s' "$ns" | sed -e 's/\\\\\\\\/\\/g' -e 's/\\\\/\\/g'
}

# Convert namespace to JSON format (double backslashes for JSON escaping)
# KYNetCode\BraCalculator -> KYNetCode\\BraCalculator
namespace_for_json() {
    local ns="$1"
    printf '%s' "$ns" | sed 's/\\/\\\\/g'
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

php_json_value() {
    php -r '
        $value = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
        foreach (explode(".", $argv[2]) as $key) {
            $value = is_array($value) && array_key_exists($key, $value) ? $value[$key] : null;
        }
        echo is_array($value) ? implode(",", $value) : (string) ($value ?? "");
    ' "$1" "$2"
}

json_array_from_csv() {
    local csv="$1"
    local output=""
    local item escaped
    IFS=',' read -r -a items <<< "$csv"
    for item in "${items[@]}"; do
        item="$(echo "$item" | xargs)"
        [[ -z "$item" ]] && continue
        escaped=$(json_escape "$item")
        [[ -n "$output" ]] && output+=","
        output+="\"$escaped\""
    done
    printf '[%s]' "$output"
}

replace_csv_item() {
    local csv="$1"
    local old_item="$2"
    local new_item="$3"
    local output=""
    local item
    local found=false
    IFS=',' read -r -a items <<< "$csv"
    for item in "${items[@]}"; do
        item="$(echo "$item" | xargs)"
        [[ -z "$item" ]] && continue
        if [[ "$item" == "$old_item" ]]; then
            item="$new_item"
            found=true
        fi
        [[ ",$output," == *",$item,"* ]] && continue
        [[ -n "$output" ]] && output+=","
        output+="$item"
    done
    if [[ "$found" == false && ",$output," != *",$new_item,"* ]]; then
        [[ -n "$output" ]] && output+=","
        output+="$new_item"
    fi
    printf '%s' "$output"
}

# Escape string for use in sed replacement
# Escapes: backslash, ampersand, and the delimiter (|)
escape_for_sed() {
    local str="$1"
    # First escape backslashes, then ampersand, then pipe (our delimiter)
    printf '%s' "$str" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g'
}

# Replace literal string in file (no regex, uses Perl for true literal matching)
# Use this for simple version replacements to avoid sed/awk regex issues
replace_literal() {
    local file="$1"
    local find="$2"
    local replace="$3"
    if [[ -f "$file" ]]; then
        # Use Perl with quotemeta (\Q...\E) for true literal string matching
        FIND="$find" REPLACE="$replace" perl -i -pe 's/\Q$ENV{FIND}\E/$ENV{REPLACE}/g' "$file"
    fi
}

# Replace in file (handles backslashes properly)
replace_in_file() {
    local file="$1"
    local find="$2"
    local replace="$3"
    if [[ -f "$file" ]]; then
        local escaped_find
        local escaped_replace
        escaped_find=$(escape_for_sed "$find")
        escaped_replace=$(escape_for_sed "$replace")
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|${escaped_find}|${escaped_replace}|g" "$file"
        else
            sed -i "s|${escaped_find}|${escaped_replace}|g" "$file"
        fi
    fi
}

# Replace in all files (excluding vendor and .git)
replace_in_all_files() {
    local find="$1"
    local replace="$2"
    local escaped_find
    local escaped_replace
    escaped_find=$(escape_for_sed "$find")
    escaped_replace=$(escape_for_sed "$replace")
    find . -type f \( -name "*.php" -o -name "*.json" -o -name "*.txt" -o -name "*.md" \) \
        -not -path "./vendor/*" -not -path "./.git/*" -not -path "./.scripts/*" | while read -r file; do
        if grep -qF "$find" "$file" 2>/dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|${escaped_find}|${escaped_replace}|g" "$file"
            else
                sed -i "s|${escaped_find}|${escaped_replace}|g" "$file"
            fi
        fi
    done
}

# Save plugin config to JSON
save_plugin_config() {
    # Escape backslashes for JSON (single backslash becomes double)
    local json_namespace
    json_namespace=$(printf '%s' "$NAMESPACE" | sed 's/\\/\\\\/g')
    local include_dirs_json include_files_json prompted_items_json
    local integrity_url_json integrity_token_json
    include_dirs_json=$(json_array_from_csv "$INCLUDE_DIRS")
    include_files_json=$(json_array_from_csv "$INCLUDE_FILES")
    prompted_items_json=$(json_array_from_csv "$PROMPTED_ITEMS")
    integrity_url_json=$(json_escape "$INTEGRITY_UPDATE_URL")
    integrity_token_json=$(json_escape "$INTEGRITY_UPDATE_TOKEN")
    
    cat > .plugin-config.json << EOF
{
  "initialized": true,
  "timestamp": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)",
  "plugin": {
    "name": "$PLUGIN_NAME",
    "slug": "$PLUGIN_SLUG",
    "namespace": "$json_namespace",
    "scoperPrefix": "$SCOPER_PREFIX",
    "dbPrefix": "$DB_PREFIX",
    "cssPrefix": "$CSS_PREFIX",
    "version": "$VERSION",
    "mainFile": "$PLUGIN_SLUG.php"
  },
  "author": {
    "name": "$AUTHOR_NAME",
    "uri": "$AUTHOR_URI"
  },
  "composer": {
    "vendor": "$VENDOR_NAME",
    "name": "$VENDOR_NAME/$PLUGIN_SLUG"
  },
  "build": {
    "includeDirs": $include_dirs_json,
    "includeFiles": $include_files_json,
    "promptedItems": $prompted_items_json,
    "integrityUpdateUrl": "$integrity_url_json",
    "integrityUpdateToken": "$integrity_token_json"
  }
}
EOF
}

# Detect current state
detect_state() {
    IS_FRESH=false
    HAS_CONFIG=false
    CURRENT_SLUG=""
    CURRENT_NAME=""
    CURRENT_NAMESPACE=""
    CURRENT_SCOPER_PREFIX=""
    CURRENT_DB_PREFIX=""
    CURRENT_CSS_PREFIX=""
    CURRENT_VERSION=""
    CURRENT_AUTHOR_NAME=""
    CURRENT_AUTHOR_URI=""
    CURRENT_VENDOR=""
    CURRENT_INCLUDE_DIRS=""
    CURRENT_INCLUDE_FILES=""
    CURRENT_PROMPTED_ITEMS=""
    CURRENT_INTEGRITY_UPDATE_URL=""
    CURRENT_INTEGRITY_UPDATE_TOKEN=""
    
    # Check for config file
    if [[ -f ".plugin-config.json" ]]; then
        HAS_CONFIG=true
        if command -v jq &> /dev/null; then
            CURRENT_NAME=$(jq -r '.plugin.name // ""' .plugin-config.json)
            CURRENT_SLUG=$(jq -r '.plugin.slug // ""' .plugin-config.json)
            CURRENT_NAMESPACE=$(jq -r '.plugin.namespace // ""' .plugin-config.json)
            CURRENT_SCOPER_PREFIX=$(jq -r '.plugin.scoperPrefix // ""' .plugin-config.json)
            CURRENT_DB_PREFIX=$(jq -r '.plugin.dbPrefix // ""' .plugin-config.json)
            CURRENT_CSS_PREFIX=$(jq -r '.plugin.cssPrefix // ""' .plugin-config.json)
            CURRENT_VERSION=$(jq -r '.plugin.version // ""' .plugin-config.json)
            CURRENT_AUTHOR_NAME=$(jq -r '.author.name // ""' .plugin-config.json)
            CURRENT_AUTHOR_URI=$(jq -r '.author.uri // ""' .plugin-config.json)
            CURRENT_VENDOR=$(jq -r '.composer.vendor // ""' .plugin-config.json)
            CURRENT_INCLUDE_DIRS=$(jq -r '.build.includeDirs // [] | join(",")' .plugin-config.json)
            CURRENT_INCLUDE_FILES=$(jq -r '.build.includeFiles // [] | join(",")' .plugin-config.json)
            CURRENT_PROMPTED_ITEMS=$(jq -r '.build.promptedItems // [] | join(",")' .plugin-config.json)
            CURRENT_INTEGRITY_UPDATE_URL=$(jq -r '.build.integrityUpdateUrl // ""' .plugin-config.json)
            CURRENT_INTEGRITY_UPDATE_TOKEN=$(jq -r '.build.integrityUpdateToken // ""' .plugin-config.json)
        elif command -v php &> /dev/null; then
            CURRENT_NAME=$(php_json_value .plugin-config.json plugin.name)
            CURRENT_SLUG=$(php_json_value .plugin-config.json plugin.slug)
            CURRENT_NAMESPACE=$(php_json_value .plugin-config.json plugin.namespace)
            CURRENT_SCOPER_PREFIX=$(php_json_value .plugin-config.json plugin.scoperPrefix)
            CURRENT_DB_PREFIX=$(php_json_value .plugin-config.json plugin.dbPrefix)
            CURRENT_CSS_PREFIX=$(php_json_value .plugin-config.json plugin.cssPrefix)
            CURRENT_VERSION=$(php_json_value .plugin-config.json plugin.version)
            CURRENT_AUTHOR_NAME=$(php_json_value .plugin-config.json author.name)
            CURRENT_AUTHOR_URI=$(php_json_value .plugin-config.json author.uri)
            CURRENT_VENDOR=$(php_json_value .plugin-config.json composer.vendor)
            CURRENT_INCLUDE_DIRS=$(php_json_value .plugin-config.json build.includeDirs)
            CURRENT_INCLUDE_FILES=$(php_json_value .plugin-config.json build.includeFiles)
            CURRENT_PROMPTED_ITEMS=$(php_json_value .plugin-config.json build.promptedItems)
            CURRENT_INTEGRITY_UPDATE_URL=$(php_json_value .plugin-config.json build.integrityUpdateUrl)
            CURRENT_INTEGRITY_UPDATE_TOKEN=$(php_json_value .plugin-config.json build.integrityUpdateToken)
        else
            echo -e "${RED}Error: jq or php is required to read .plugin-config.json safely.${NC}"
            return 1
        fi
    fi
    
    # Check for fresh install
    if [[ -f "my-plugin.php" ]]; then
        IS_FRESH=true
    fi
    
    # If no config but not fresh, try to detect from files
    if [[ "$HAS_CONFIG" == "false" && "$IS_FRESH" == "false" ]]; then
        # Find the main plugin file (*.php with Plugin Name header in root)
        MAIN_FILE=$(grep -l "Plugin Name:" *.php 2>/dev/null | head -1)
        if [[ -n "$MAIN_FILE" ]]; then
            CURRENT_SLUG="${MAIN_FILE%.php}"
            CURRENT_NAME=$(grep -oP "Plugin Name:\s*\K.*" "$MAIN_FILE" | head -1 | xargs)
            # Try to detect namespace from composer.json
            if [[ -f "composer.json" ]]; then
                local raw_ns_composer
                raw_ns_composer=$(grep -oP '"[^"]+\\\\\\\\": "app/"' composer.json 2>/dev/null | head -1 | cut -d'"' -f2)
                CURRENT_NAMESPACE=$(normalize_namespace "$raw_ns_composer")
            fi
        fi
    fi
}

# ============================================================================
# Main Script
# ============================================================================

print_header

# Detect current state
detect_state

# Show current status
if [[ "$IS_FRESH" == "true" ]]; then
    echo -e "${GREEN}Fresh scaffold detected.${NC}"
    echo ""
elif [[ "$HAS_CONFIG" == "true" ]]; then
    echo -e "${CYAN}Current Configuration:${NC}"
    echo -e "  ${GRAY}Plugin Name:${NC}  $CURRENT_NAME"
    echo -e "  ${GRAY}Slug:${NC}         $CURRENT_SLUG"
    echo -e "  ${GRAY}Namespace:${NC}    $CURRENT_NAMESPACE"
    echo -e "  ${GRAY}DB Prefix:${NC}    $CURRENT_DB_PREFIX"
    echo -e "  ${GRAY}Vendor:${NC}       $CURRENT_VENDOR"
    echo ""
    echo -e "${YELLOW}You can update any value or press Enter to keep current.${NC}"
    echo ""
elif [[ -n "$CURRENT_SLUG" ]]; then
    echo -e "${YELLOW}Config file missing but plugin detected: $CURRENT_SLUG${NC}"
    echo -e "${GRAY}Values will be auto-detected where possible.${NC}"
    echo ""
else
    echo -e "${RED}Error: Cannot detect plugin state.${NC}"
    echo -e "${RED}Expected 'my-plugin.php' for fresh install or '.plugin-config.json' for existing.${NC}"
    exit 1
fi

# ============================================================================
# Collect Information
# ============================================================================

# Set defaults based on state
if [[ "$IS_FRESH" == "true" ]]; then
    DEFAULT_NAME="My Plugin"
    DEFAULT_SLUG="my-plugin"
    DEFAULT_NAMESPACE="MyPlugin"
    DEFAULT_SCOPER_PREFIX="my_plugin"
    DEFAULT_DB_PREFIX="myplugin_"
    DEFAULT_CSS_PREFIX="mp-"
    DEFAULT_VERSION="1.0.0"
    DEFAULT_AUTHOR_NAME="Your Name"
    DEFAULT_AUTHOR_URI="https://example.com"
    DEFAULT_VENDOR="yourname"
    DEFAULT_INCLUDE_DIRS="app,bootstrap,config,resources,routes"
    DEFAULT_INCLUDE_FILES="composer.json,LICENSE,readme.txt,uninstall.php,my-plugin.php"
    DEFAULT_PROMPTED_ITEMS=""
    DEFAULT_INTEGRITY_UPDATE_URL="https://license-verification.test/api/v1/plugin/integrity"
    DEFAULT_INTEGRITY_UPDATE_TOKEN="wpzylos-local-integrity-update-token-2026"
else
    DEFAULT_NAME="${CURRENT_NAME:-My Plugin}"
    DEFAULT_SLUG="${CURRENT_SLUG:-my-plugin}"
    DEFAULT_NAMESPACE="${CURRENT_NAMESPACE:-MyPlugin}"
    DEFAULT_SCOPER_PREFIX="${CURRENT_SCOPER_PREFIX:-my_plugin}"
    DEFAULT_DB_PREFIX="${CURRENT_DB_PREFIX:-myplugin_}"
    DEFAULT_CSS_PREFIX="${CURRENT_CSS_PREFIX:-mp-}"
    DEFAULT_VERSION="${CURRENT_VERSION:-1.0.0}"
    DEFAULT_AUTHOR_NAME="${CURRENT_AUTHOR_NAME:-Your Name}"
    DEFAULT_AUTHOR_URI="${CURRENT_AUTHOR_URI:-https://example.com}"
    DEFAULT_VENDOR="${CURRENT_VENDOR:-yourname}"
    DEFAULT_INCLUDE_DIRS="$CURRENT_INCLUDE_DIRS"
    DEFAULT_INCLUDE_FILES="$CURRENT_INCLUDE_FILES"
    DEFAULT_PROMPTED_ITEMS="$CURRENT_PROMPTED_ITEMS"
    DEFAULT_INTEGRITY_UPDATE_URL="${CURRENT_INTEGRITY_UPDATE_URL:-https://license-verification.test/api/v1/plugin/integrity}"
    DEFAULT_INTEGRITY_UPDATE_TOKEN="${CURRENT_INTEGRITY_UPDATE_TOKEN:-wpzylos-local-integrity-update-token-2026}"
fi

echo "Enter your plugin display name (or press Enter to keep current):"
PLUGIN_NAME=$(read_with_default "> Plugin Name" "$DEFAULT_NAME")

# Only derive new values if name changed
if [[ "$PLUGIN_NAME" != "$DEFAULT_NAME" ]]; then
    DERIVED_SLUG=$(to_slug "$PLUGIN_NAME")
    DERIVED_NAMESPACE=$(to_namespace "$DERIVED_SLUG")
    DERIVED_SCOPER_PREFIX=$(to_scoper_prefix "$DERIVED_SLUG")
    DERIVED_DB_PREFIX=$(to_db_prefix "$DERIVED_SLUG")
    DERIVED_CSS_PREFIX=$(convert_to_css_prefix "$PLUGIN_NAME")
else
    DERIVED_SLUG="$DEFAULT_SLUG"
    DERIVED_NAMESPACE="$DEFAULT_NAMESPACE"
    DERIVED_SCOPER_PREFIX="$DEFAULT_SCOPER_PREFIX"
    DERIVED_DB_PREFIX="$DEFAULT_DB_PREFIX"
    DERIVED_CSS_PREFIX="$DEFAULT_CSS_PREFIX"
fi

echo ""
echo "Derived/Current values (press Enter to accept, or type to override):"

PLUGIN_SLUG=$(read_with_default "  Plugin Slug" "$DERIVED_SLUG")
NAMESPACE=$(read_with_default "  PHP Namespace" "$DERIVED_NAMESPACE")
# Normalize namespace: convert \\ or \\\ to single \
NAMESPACE=$(normalize_namespace "$NAMESPACE")
SCOPER_PREFIX=$(read_with_default "  Scoper Prefix" "$DERIVED_SCOPER_PREFIX")
DB_PREFIX=$(read_with_default "  Database Prefix" "$DERIVED_DB_PREFIX")
CSS_PREFIX=$(read_with_default "  CSS Prefix" "$DERIVED_CSS_PREFIX")

echo ""
echo "Author information (press Enter to keep current):"
AUTHOR_NAME=$(read_with_default "  Author Name" "$DEFAULT_AUTHOR_NAME")
AUTHOR_URI=$(read_with_default "  Author URI" "$DEFAULT_AUTHOR_URI")
# Plugin URI - derive from Author URI if available
if [[ "$AUTHOR_URI" != "https://example.com" && -n "$AUTHOR_URI" ]]; then
    DERIVED_PLUGIN_URI="$AUTHOR_URI/$PLUGIN_SLUG"
else
    DERIVED_PLUGIN_URI="https://example.com/$PLUGIN_SLUG"
fi
PLUGIN_URI=$(read_with_default "  Plugin URI" "$DERIVED_PLUGIN_URI")

# Vendor name
if [[ "$AUTHOR_NAME" != "$DEFAULT_AUTHOR_NAME" ]]; then
    NEW_DEFAULT_VENDOR=$(to_vendor "$AUTHOR_NAME")
else
    NEW_DEFAULT_VENDOR="$DEFAULT_VENDOR"
fi
VENDOR_NAME=$(read_with_default "  Vendor Name (for composer)" "$NEW_DEFAULT_VENDOR" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')

# Version
VERSION=$(read_with_default "  Version" "$DEFAULT_VERSION")

echo ""
echo "Build configuration (comma-separated; type <none> to clear a list):"
INCLUDE_DIRS=$(read_list_with_default "  Include Directories" "$DEFAULT_INCLUDE_DIRS")
INCLUDE_FILES=$(read_list_with_default "  Include Files" "$DEFAULT_INCLUDE_FILES")
PROMPTED_ITEMS=$(read_list_with_default "  Previously Prompted Items" "$DEFAULT_PROMPTED_ITEMS")
INTEGRITY_UPDATE_URL=$(read_with_default "  Integrity API Endpoint" "$DEFAULT_INTEGRITY_UPDATE_URL")
INTEGRITY_UPDATE_TOKEN=$(read_with_default "  Integrity API Key/Token" "$DEFAULT_INTEGRITY_UPDATE_TOKEN")

# Determine what needs to change
OLD_NAME="${CURRENT_NAME:-My Plugin}"
OLD_SLUG="${CURRENT_SLUG:-my-plugin}"
OLD_NAMESPACE="${CURRENT_NAMESPACE:-MyPlugin}"
OLD_SCOPER_PREFIX="${CURRENT_SCOPER_PREFIX:-my_plugin}"
OLD_DB_PREFIX="${CURRENT_DB_PREFIX:-myplugin_}"
OLD_VENDOR="${CURRENT_VENDOR:-KYNetCode}"

# For fresh install, use scaffold defaults
if [[ "$IS_FRESH" == "true" ]]; then
    OLD_NAME="My Plugin"
    OLD_SLUG="my-plugin"
    OLD_NAMESPACE="MyPlugin"
    OLD_SCOPER_PREFIX="my_plugin"
    OLD_DB_PREFIX="myplugin_"
    OLD_VENDOR="KYNetCode"
fi

echo ""
echo -e "${WHITE}Summary:${NC}"
echo -e "  ${GRAY}Plugin Name:${NC}    $PLUGIN_NAME"
echo -e "  ${GRAY}Plugin Slug:${NC}    $PLUGIN_SLUG"
echo -e "  ${GRAY}Namespace:${NC}      $NAMESPACE"
echo -e "  ${GRAY}Scoper Prefix:${NC}  $SCOPER_PREFIX"
echo -e "  ${GRAY}DB Prefix:${NC}      $DB_PREFIX"
echo -e "  ${GRAY}CSS Prefix:${NC}     $CSS_PREFIX"
echo -e "  ${GRAY}Version:${NC}        $VERSION"
echo -e "  ${GRAY}Vendor:${NC}         $VENDOR_NAME"
echo -e "  ${GRAY}Composer Name:${NC}  $VENDOR_NAME/$PLUGIN_SLUG"
echo -e "  ${GRAY}Include Dirs:${NC}   $INCLUDE_DIRS"
echo -e "  ${GRAY}Include Files:${NC}  $INCLUDE_FILES"
echo -e "  ${GRAY}Integrity API:${NC}  $INTEGRITY_UPDATE_URL"
echo ""

read -r -p "Proceed with initialization? [Y/n]: " CONFIRM
if [[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

echo ""

# ============================================================================
# Perform Replacements (only if values changed)
# ============================================================================

TOTAL_STEPS=10
MAIN_PLUGIN_FILE="${OLD_SLUG}.php"
if [[ "$IS_FRESH" == "true" ]]; then
    MAIN_PLUGIN_FILE="my-plugin.php"
fi

# Step 1: Replace display name
print_step 1 $TOTAL_STEPS "Replacing display name"
if [[ "$PLUGIN_NAME" != "$OLD_NAME" ]]; then
    replace_in_all_files "$OLD_NAME" "$PLUGIN_NAME"
    print_done
else
    print_skip
fi

# Step 2: Replace plugin slug
print_step 2 $TOTAL_STEPS "Replacing plugin slug"
if [[ "$PLUGIN_SLUG" != "$OLD_SLUG" ]]; then
    replace_in_all_files "$OLD_SLUG" "$PLUGIN_SLUG"
    print_done
else
    print_skip
fi

# Step 3: Replace namespace
print_step 3 $TOTAL_STEPS "Replacing namespace"
if [[ "$NAMESPACE" != "$OLD_NAMESPACE" ]]; then
    # For PHP, TXT, MD files - use single backslash namespace
    escaped_old_ns=$(escape_for_sed "$OLD_NAMESPACE")
    escaped_new_ns=$(escape_for_sed "$NAMESPACE")
    find . -type f \( -name "*.php" -o -name "*.txt" -o -name "*.md" \) \
        -not -path "./vendor/*" -not -path "./.git/*" -not -path "./.scripts/*" | while read -r file; do
        if grep -qF "$OLD_NAMESPACE" "$file" 2>/dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|${escaped_old_ns}|${escaped_new_ns}|g" "$file"
            else
                sed -i "s|${escaped_old_ns}|${escaped_new_ns}|g" "$file"
            fi
        fi
    done
    # For JSON files - use double backslash namespace (JSON escaping)
    old_json_ns=$(namespace_for_json "$OLD_NAMESPACE")
    new_json_ns=$(namespace_for_json "$NAMESPACE")
    escaped_old_json=$(escape_for_sed "$old_json_ns")
    escaped_new_json=$(escape_for_sed "$new_json_ns")
    find . -type f -name "*.json" \
        -not -path "./vendor/*" -not -path "./.git/*" | while read -r file; do
        if grep -qF "$old_json_ns" "$file" 2>/dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|${escaped_old_json}|${escaped_new_json}|g" "$file"
            else
                sed -i "s|${escaped_old_json}|${escaped_new_json}|g" "$file"
            fi
        fi
    done
    # Also update the 'namespace' => 'Value' and 'name' => 'Value' in PluginContext::create()
    replace_literal "$MAIN_PLUGIN_FILE" "'namespace'  => '$OLD_NAMESPACE'" "'namespace'  => '$NAMESPACE'"
    replace_literal "$MAIN_PLUGIN_FILE" "'namespace' => '$OLD_NAMESPACE'" "'namespace' => '$NAMESPACE'"
    print_done
else
    print_skip
fi

# Step 4: Replace scoper prefix
print_step 4 $TOTAL_STEPS "Replacing scoper prefix"
if [[ "$SCOPER_PREFIX" != "$OLD_SCOPER_PREFIX" ]]; then
    replace_in_file "scoper.inc.php" "$OLD_SCOPER_PREFIX" "$SCOPER_PREFIX"
    print_done
else
    print_skip
fi

# Step 5: Replace database prefix
print_step 5 $TOTAL_STEPS "Replacing database prefix"
if [[ "$DB_PREFIX" != "$OLD_DB_PREFIX" ]]; then
    replace_in_all_files "$OLD_DB_PREFIX" "$DB_PREFIX"
    print_done
else
    print_skip
fi

# Step 5b: Replace CSS prefix
print_step 5 $TOTAL_STEPS "Replacing CSS prefix"
CSS_NOHYPHEN="${CSS_PREFIX%-}"
# Fresh install / placeholder replacement: swap __CSS_PREFIX__ tokens across all eligible files
find . -type f \( -name "*.css" -o -name "*.js" -o -name "*.json" -o -name "*.php" \) \
    -not -path "./vendor/*" -not -path "./.git/*" -not -path "./.scripts/*" | while read -r file; do
    if grep -q '__CSS_PREFIX__\|__CSS_PREFIX_NOHYPHEN__' "$file" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|__CSS_PREFIX__|${CSS_PREFIX}|g; s|__CSS_PREFIX_NOHYPHEN__|${CSS_NOHYPHEN}|g" "$file"
        else
            sed -i "s|__CSS_PREFIX__|${CSS_PREFIX}|g; s|__CSS_PREFIX_NOHYPHEN__|${CSS_NOHYPHEN}|g" "$file"
        fi
        echo -e "    ${GRAY}Updated: $(basename "$file")${NC}"
    fi
done
# Re-init: update existing css_prefix value in config/ui.php when the prefix has changed
OLD_CSS_FOR_FILE="${CURRENT_CSS_PREFIX:-mp-}"
if [[ "$CSS_PREFIX" != "$OLD_CSS_FOR_FILE" ]]; then
    replace_literal "config/ui.php" "'css_prefix' => '$OLD_CSS_FOR_FILE'" "'css_prefix' => '$CSS_PREFIX'"
    echo -e "    ${GRAY}Updated: config/ui.php (css_prefix: $OLD_CSS_FOR_FILE -> $CSS_PREFIX)${NC}"
fi
print_done

# Step 5c: Update plugin display name in PluginContext::create()
print_step 5 $TOTAL_STEPS "Updating plugin display name in PluginContext"
if [[ "$PLUGIN_NAME" != "$OLD_NAME" ]]; then
    replace_literal "$MAIN_PLUGIN_FILE" "'name'       => '$OLD_NAME'" "'name'       => '$PLUGIN_NAME'"
    replace_literal "$MAIN_PLUGIN_FILE" "'name' => '$OLD_NAME'" "'name' => '$PLUGIN_NAME'"
fi
print_done

# Step 6: Replace global variable
print_step 6 $TOTAL_STEPS "Replacing global variable name"
if [[ "$PLUGIN_SLUG" != "$OLD_SLUG" ]]; then
    OLD_GLOBAL_VAR="\$$(echo "$OLD_SLUG" | tr '-' '_')_context"
    NEW_GLOBAL_VAR="\$$(echo "$PLUGIN_SLUG" | tr '-' '_')_context"
    OLD_GLOBAL_CONTEXT_KEY="\$GLOBALS['$(echo "$OLD_SLUG" | tr '-' '_')_context']"
    NEW_GLOBAL_CONTEXT_KEY="\$GLOBALS['$(echo "$PLUGIN_SLUG" | tr '-' '_')_context']"
    OLD_GLOBAL_APP_KEY="\$GLOBALS['$(echo "$OLD_SLUG" | tr '-' '_')_app']"
    NEW_GLOBAL_APP_KEY="\$GLOBALS['$(echo "$PLUGIN_SLUG" | tr '-' '_')_app']"
    replace_in_file "$MAIN_PLUGIN_FILE" "$OLD_GLOBAL_VAR" "$NEW_GLOBAL_VAR"
    replace_literal "$MAIN_PLUGIN_FILE" "$OLD_GLOBAL_CONTEXT_KEY" "$NEW_GLOBAL_CONTEXT_KEY"
    replace_literal "app/Core/Plugin.php" "$OLD_GLOBAL_APP_KEY" "$NEW_GLOBAL_APP_KEY"
    print_done
else
    print_skip
fi

# Step 7: Update composer.json package name
print_step 7 $TOTAL_STEPS "Updating composer.json package name"
if [[ "$VENDOR_NAME" != "$OLD_VENDOR" || "$PLUGIN_SLUG" != "$OLD_SLUG" ]]; then
    replace_in_file "composer.json" "$OLD_VENDOR/$OLD_SLUG" "$VENDOR_NAME/$PLUGIN_SLUG"
    # Also update if still has scaffold name
    replace_in_file "composer.json" "KYNetCode/wpzylos-scaffold" "$VENDOR_NAME/$PLUGIN_SLUG"
    print_done
else
    print_skip
fi

# Step 8: Update author information
print_step 8 $TOTAL_STEPS "Updating author information"
replace_in_file "$MAIN_PLUGIN_FILE" "Your Name" "$AUTHOR_NAME"
replace_in_file "$MAIN_PLUGIN_FILE" "https://example.com/$OLD_SLUG" "$PLUGIN_URI"
replace_in_file "$MAIN_PLUGIN_FILE" "https://example.com" "$AUTHOR_URI"
AUTHOR_USERNAME=$(to_vendor "$AUTHOR_NAME")
replace_in_file "readme.txt" "your-username" "$AUTHOR_USERNAME"
print_done

# Step 8b: Update version in files
print_step 8 $TOTAL_STEPS "Updating version"
OLD_VERSION="${CURRENT_VERSION:-1.0.0}"
# Get the actual main plugin file (after possible rename)
if [[ "$PLUGIN_SLUG" != "$OLD_SLUG" && -f "$PLUGIN_SLUG.php" ]]; then
    ACTUAL_MAIN_FILE="$PLUGIN_SLUG.php"
else
    ACTUAL_MAIN_FILE="$MAIN_PLUGIN_FILE"
fi
if [[ "$VERSION" != "$OLD_VERSION" ]]; then
    # Update plugin header Version (format: "* Version: X.X.X") - use replace_literal to avoid sed regex issues
    replace_literal "$ACTUAL_MAIN_FILE" "Version: $OLD_VERSION" "Version: $VERSION"
    # Update PluginContext version (format: "'version' => 'X.X.X'")
    replace_literal "$ACTUAL_MAIN_FILE" "'version' => '$OLD_VERSION'" "'version' => '$VERSION'"
    # Update readme.txt Stable tag
    replace_literal "readme.txt" "Stable tag: $OLD_VERSION" "Stable tag: $VERSION"
    print_done
else
    print_skip
fi

# Step 9: Rename main plugin file
print_step 9 $TOTAL_STEPS "Renaming plugin file"
if [[ -f "$MAIN_PLUGIN_FILE" && "$PLUGIN_SLUG" != "$OLD_SLUG" ]]; then
    replace_in_file "scoper.inc.php" "$MAIN_PLUGIN_FILE" "$PLUGIN_SLUG.php"
    replace_in_file "uninstall.php" "$MAIN_PLUGIN_FILE" "$PLUGIN_SLUG.php"
    mv "$MAIN_PLUGIN_FILE" "$PLUGIN_SLUG.php"
    print_done
else
    print_skip
fi

# Step 10: Save configuration
print_step 10 $TOTAL_STEPS "Saving plugin configuration"
INCLUDE_FILES=$(replace_csv_item "$INCLUDE_FILES" "$MAIN_PLUGIN_FILE" "$PLUGIN_SLUG.php")
save_plugin_config
print_done

# ============================================================================
# Post-Processing
# ============================================================================

echo ""
echo -e "${YELLOW}Running composer dump-autoload...${NC}"

if composer dump-autoload 2>/dev/null; then
    print_success "Composer autoload updated"
else
    echo -e "${YELLOW}Warning: composer dump-autoload failed. Run it manually.${NC}"
fi

# ============================================================================
# Success Message
# ============================================================================

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Plugin '$PLUGIN_NAME' configured!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "Configuration saved to: .plugin-config.json"
echo ""
echo "Next steps:"
echo -e "${GRAY}  1. Run: composer install${NC}"
echo -e "${GRAY}  2. Develop your plugin${NC}"
echo -e "${GRAY}  3. Build: ./scaffold.sh build${NC}"
echo ""
