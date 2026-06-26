<?php

declare(strict_types=1);

namespace MyPlugin\Providers;

use WPZylos\Framework\Core\ServiceProvider;
use WPZylos\Framework\Core\Contracts\ApplicationInterface;

/**
 * Application Service Provider.
 *
 * Register your plugin's own bindings, singletons, and services here.
 * This is the Laravel-style entry point for your custom DI wiring.
 *
 * Usage examples:
 *
 *   // Bind an interface to a concrete class:
 *   $this->bind( MyInterface::class, MyConcreteClass::class );
 *
 *   // Register a singleton:
 *   $this->singleton( MyService::class, fn() => new MyService() );
 *
 *   // Resolve from container:
 *   $service = $this->make( MyService::class );
 *
 * @package MyPlugin\Providers
 */
class AppServiceProvider extends ServiceProvider
{
    /**
     * Register bindings in the container.
     *
     * Called before boot(). Use this for all DI registrations.
     *
     * @param ApplicationInterface $app The application instance
     *
     * @return void
     */
    public function register(ApplicationInterface $app): void
    {
        parent::register($app);

        // Register your services here.
        //
        // Examples:
        // $this->singleton( MyService::class );
        // $this->bind( RepositoryInterface::class, EloquentRepository::class );
    }

    /**
     * Bootstrap your services after all providers are registered.
     *
     * Called after all register() methods. Safe to use other services here.
     *
     * @param ApplicationInterface $app The application instance
     *
     * @return void
     */
    public function boot(ApplicationInterface $app): void
    {
        // Bootstrap your services here.
        //
        // Examples:
        // add_action( 'init', [ $this->make( MyService::class ), 'init' ] );
    }
}
