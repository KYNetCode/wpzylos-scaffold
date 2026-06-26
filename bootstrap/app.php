<?php

/**
 * Bootstrap the application.
 *
 * Boot sequence:
 * 1. RequirementsGate → Context → Autoload   (main plugin file)
 * 2. Activation / Deactivation hooks          (main plugin file)
 * 3. Bootstrap: container + providers         (this file)
 * 4. Boot the application                     (this file)
 *
 * Which service providers are loaded is controlled by config/app.php.
 * Only uncomment the providers your plugin actually needs.
 *
 * @package MyPlugin
 */

declare( strict_types=1 );

use MyPlugin\Core\PluginContext;
use WPZylos\Framework\Container\Container;
use WPZylos\Framework\Core\Application;

/**
 * Bootstrap the application.
 *
 * @param PluginContext $context Plugin context
 *
 * @return Application
 */
return static function ( PluginContext $context ): Application {
	// ── 1. Create container + application ────────────────────────────────
	$container = new Container();
	$app       = new Application( $context, $container );

	// ── 2. Load provider list from config/app.php ─────────────────────────
	$config    = require $context->path( 'config/app.php' );
	$providers = $config['providers'] ?? [];

	// ── 3. Register each provider ─────────────────────────────────────────
	foreach ( $providers as $providerClass ) {
		if ( class_exists( $providerClass ) ) {
			$app->register( new $providerClass() );
		}
	}

	// ── 4. Boot the application ───────────────────────────────────────────
	$app->boot();

	return $app;
};
