<?php

declare(strict_types=1);

namespace MyPlugin\Core;

use MyPlugin\Lifecycle\Activator;
use MyPlugin\Lifecycle\Deactivator;

/**
 * Handles lifecycle hook registration, requirement checks, and application boot.
 *
 * @package MyPlugin\Core
 */
final class Plugin
{
    public static function register(PluginContext $context): void
    {
        register_activation_hook(
            $context->file(),
            static function () use ($context): void {
                Activator::activate($context);
            }
        );

        register_deactivation_hook(
            $context->file(),
            static function () use ($context): void {
                Deactivator::deactivate($context);
            }
        );

        add_action(
            'admin_init',
            static function () use ($context): void {
                self::enforceRequirements($context);
            }
        );

        add_action(
            'plugins_loaded',
            static function () use ($context): void {
                self::boot($context);
            }
        );
    }

    private static function boot(PluginContext $context): void
    {
        $bootstrapPath = $context->path('bootstrap/app.php');

        if (! is_readable($bootstrapPath)) {
            return;
        }

        $bootstrap = require $bootstrapPath;

        if (is_callable($bootstrap)) {
            $GLOBALS['my_plugin_app'] = $bootstrap($context);
        }
    }

    private static function enforceRequirements(PluginContext $context): void
    {
        $message = null;

        if (PHP_VERSION_ID < 80100) {
            $message = sprintf(
                /* translators: %s: Required PHP version. */
                __('My Plugin requires PHP version %s or higher.', $context->textDomain()),
                '8.1'
            );
        } elseif (version_compare(get_bloginfo('version'), '6.0', '<')) {
            $message = sprintf(
                /* translators: %s: Required WordPress version. */
                __('My Plugin requires WordPress version %s or higher.', $context->textDomain()),
                '6.0'
            );
        }

        if ($message === null) {
            return;
        }

        add_action(
            'admin_notices',
            static function () use ($message): void {
                printf(
                    '<div class="notice notice-error"><p>%s</p></div>',
                    esc_html($message)
                );
            }
        );

        deactivate_plugins(plugin_basename($context->file()));
    }
}
