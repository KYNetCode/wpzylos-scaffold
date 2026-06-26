<?php

/**
 * Plugin Name: My Plugin
 * Plugin URI: https://example.com/my-plugin
 * Description: A plugin built with WPZylos framework.
 * Version: 1.0.0
 * Author: Your Name
 * Author URI: https://example.com
 * License: GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: my-plugin
 * Domain Path: /resources/lang
 * Requires at least: 6.0
 * Requires PHP: 8.1
 *
 * @package MyPlugin
 */

declare(strict_types=1);

defined('ABSPATH') || exit;

if (file_exists(__DIR__ . '/vendor/autoload.php')) {
    require_once __DIR__ . '/vendor/autoload.php';
}

use MyPlugin\Core\Plugin;
use MyPlugin\Core\PluginContext;

$context = PluginContext::forPluginFile(__FILE__);
$GLOBALS['my_plugin_context'] = $context;

Plugin::register($context);
