<?php

/**
 * Application configuration.
 *
 * @package MyPlugin
 */

return [
	/**
	 * Application name.
	 */
	'name'       => 'My Plugin',

	/**
	 * Debug mode.
	 */
	'debug'      => defined( 'WP_DEBUG' ) && WP_DEBUG,

	/**
	 * Settings page capability.
	 */
	'capability' => 'manage_options',

	/**
	 * Service Providers.
	 *
	 * List the service providers that should be loaded for your plugin.
	 * Only include what you actually need — unused providers waste memory.
	 *
	 * CORE (always required — do not remove these):
	 *   ConfigServiceProvider  → config loading
	 *   LoggerServiceProvider  → PSR-3 error/debug logging
	 *   I18nServiceProvider    → translations / text domain
	 *   HookServiceProvider    → WordPress action/filter manager
	 *
	 * OPTIONAL (uncomment only what your plugin uses):
	 *   EventServiceProvider      → PSR-14 event dispatching
	 *   SecurityServiceProvider   → nonces, sanitization, rate-limiting
	 *   HttpServiceProvider       → Request/Response/Pipeline
	 *   ValidationServiceProvider → form/input validation
	 *   ViewsServiceProvider      → PHP/Twig template rendering
	 *   DatabaseServiceProvider   → query builder / raw DB access
	 *   ModelServiceProvider      → ORM-style model layer (needs Database)
	 *   MigrationsServiceProvider → DB schema migrations (needs Database)
	 *   RoutingServiceProvider    → REST API / frontend routes
	 *   AssetsServiceProvider     → script/style enqueueing + Vite
	 *   SchedulerServiceProvider  → WP-Cron task scheduling
	 *   QueueServiceProvider      → background job queue
	 *   MailServiceProvider       → fluent email sending
	 *   NotificationServiceProvider → multi-channel notifications
	 *   WpCliServiceProvider      → WP-CLI commands (auto-skipped if not CLI)
	 *
	 * YOUR PLUGIN'S OWN PROVIDERS (always keep this):
	 *   AppServiceProvider → register your own bindings and services
	 */
	'providers'  => [
		// ── Core (required) ──────────────────────────────────────────────
		\WPZylos\Framework\Config\ConfigServiceProvider::class,
		\WPZylos\Framework\Logger\LoggerServiceProvider::class,
		\WPZylos\Framework\I18n\I18nServiceProvider::class,
		\WPZylos\Framework\Hooks\HookServiceProvider::class,

		// ── Optional framework providers ─────────────────────────────────
		// \WPZylos\Framework\Events\EventServiceProvider::class,
		// \WPZylos\Framework\Security\SecurityServiceProvider::class,
		// \WPZylos\Framework\Http\HttpServiceProvider::class,
		// \WPZylos\Framework\Validation\ValidationServiceProvider::class,
		// \WPZylos\Framework\Views\ViewsServiceProvider::class,
		// \WPZylos\Framework\Database\DatabaseServiceProvider::class,
		// \WPZylos\Framework\Model\ModelServiceProvider::class,
		// \WPZylos\Framework\Migrations\MigrationsServiceProvider::class,
		// \WPZylos\Framework\Routing\RoutingServiceProvider::class,
		// \WPZylos\Framework\Assets\AssetsServiceProvider::class,
		// \WPZylos\Framework\Scheduler\SchedulerServiceProvider::class,
		// \WPZylos\Framework\Queue\QueueServiceProvider::class,
		// \WPZylos\Framework\Mail\MailServiceProvider::class,
		// \WPZylos\Framework\Notification\NotificationServiceProvider::class,
		// \WPZylos\Framework\WpCli\WpCliServiceProvider::class,

		// ── Your plugin providers ─────────────────────────────────────────
		\MyPlugin\Providers\AppServiceProvider::class,
	],
];
