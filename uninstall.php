<?php

/**
 * WordPress uninstall entry point.
 *
 * WordPress discovers this root file automatically when the plugin is deleted.
 * All uninstall decisions and cleanup live in the Lifecycle Uninstaller.
 *
 * @package MyPlugin
 */

declare(strict_types=1);

use MyPlugin\Core\PluginContext;
use MyPlugin\Lifecycle\Uninstaller;

defined('WP_UNINSTALL_PLUGIN') || exit;

$pluginFile = __DIR__ . '/my-plugin.php';
$autoload   = dirname($pluginFile) . '/vendor/autoload.php';

if (! is_readable($autoload)) {
    return;
}

require_once $autoload;

$context = PluginContext::forPluginFile($pluginFile);

Uninstaller::uninstall($context);
