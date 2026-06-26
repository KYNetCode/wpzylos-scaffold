# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - 2026-02-04

### 🚀 WPZylos Scaffold v1.1.0

Introducing a unified **Scaffold CLI** that streamlines plugin initialization and production builds.

### ✨ New Features

#### Unified Scaffold CLI

- New `scaffold.ps1` (Windows) and `scaffold` (Linux/Mac) entry point
- Interactive menu to choose between init and build actions
- Direct commands: `./scaffold init` or `./scaffold build`

#### Integrated QA Pipeline

- Automatic **phpcbf** (PSR-12) code style fixes before build
- Automatic **phpstan** static analysis before build
- Skip with `--skip-qa` flag when needed

#### Shared Configuration

- New `.plugin-config.json` stores plugin settings after initialization
- Build script reads config for versioned ZIP creation
- No more manual configuration between init and build

### ✨ Intelligent Init Script

- **Smart state detection**: Handles fresh install, re-configuration, and deleted config scenarios
- **Namespace normalization**: Accepts single, double, or triple backslashes - all work correctly
- **Partial updates**: Only replaces changed values, shows "Skipped" for unchanged fields
- **Proper backslash handling**: Fixed sed escape issues for namespaces like `KYNetCode\WPBraCalculator`
- **Smart Plugin URI**: Auto-derives Plugin URI from Author URI + plugin slug

### 📖 Documentation Improvements

- Added **Command Prompt** instructions for Windows users
- Improved CLI documentation with clear Option 1/2/3 format
- Added Git Bash alternative syntax: `bash scaffold`
- Link to Git for Windows download

### 🔧 Build Improvements

- `phpstan.neon` now tracked directly (not .dist) for streamlined builds
- PHPStan configuration includes WordPress stubs out of the box

### 🔄 CI/CD

- Packagist auto-update workflow with dynamic repository URL
- Fixed workflow triggers and authentication

### 🐛 Bug Fixes

- Fixed `unterminated 's' command` error when namespace contains backslash
- Fixed terminal escape codes corrupting namespace input
- Fixed namespace not saving correctly to `.plugin-config.json`
- Fixed JSON namespace escaping: Namespaces now use double backslash in `composer.json`

**Full Changelog**: https://github.com/KYNetCode/wpzylos-scaffold/compare/v1.0.0...v1.1.0

## v1.0.0 - 2026-02-01

First stable release of wpzylos-scaffold

## [Unreleased]

### Added

- Canonical `app/Core/Plugin.php` bootstrap coordinator for requirements, lifecycle hooks, and application startup.
- Template-safe `config/ui.php` plus PHPStan stubs for Elementor and WooCommerce admin helper functions.
- Build/init support for version, PHPStan memory limit, integrity update URL/token, CSS prefix, and existing `.plugin-config.json` values.

### Changed

- Main plugin and uninstall entrypoints now create context via `PluginContext::forPluginFile(__FILE__)`.
- `PluginContext` now exposes plugin name/config helpers and header-based version detection.
- Uninstall cleanup now keeps/removes plugin data through `Uninstaller::shouldKeepData()`.
- Scoper defaults now include app/bootstrap/config/routes while excluding WordPress, Elementor, WPBakery, WooCommerce, and common WP APIs.
- Scaffold frontend defaults now use PHP/Twig view wording and scoped CSS placeholders.

### Deprecated

### Removed

- Removed scaffold Blade template examples because `wpzylos-views` does not provide a Blade engine.

### Fixed

- Init scripts now preserve existing build configuration keys while updating include lists and plugin identity fields.
- PowerShell init replacements now avoid case-insensitive namespace substitutions corrupting lowercase prefixes.

### Security
