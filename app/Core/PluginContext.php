<?php

declare(strict_types=1);

namespace MyPlugin\Core;

use WPZylos\Framework\Config\ConfigRepository;
use WPZylos\Framework\Core\Contracts\ContextInterface;

/**
 * Plugin Context - Core configuration and utility class.
 *
 * This class is owned by the plugin and survives PHP-Scoper namespace rewriting.
 * Framework packages use ContextInterface.
 *
 * @package MyPlugin\Core
 * @since   1.0.0
 */
class PluginContext implements ContextInterface
{
    private string $file;
    private string $slug;
    private string $prefix;
    private string $textDomain;
    private string $version;
    private string $namespace;
    private string $name;
    private ?string $commit = null;
    private ?ConfigRepository $configRepo = null;

    /** @var array<string, mixed> */
    private array $extra = [];

    private ?string $basePath = null;
    private ?string $baseUrl = null;

    /**
     * @param array{
     *     file: string,
     *     slug: string,
     *     name?: string,
     *     prefix: string,
     *     textDomain: string,
     *     version: string,
     *     namespace: string,
     *     commit?: string|null,
     *     extra?: array<string, mixed>
     * } $config
     */
    private function __construct(array $config)
    {
        $this->file       = $config['file'];
        $this->slug       = $config['slug'];
        $this->prefix     = $config['prefix'];
        $this->textDomain = $config['textDomain'];
        $this->version    = $config['version'];
        $this->namespace  = $config['namespace'];
        $this->name       = $config['name'] ?? $config['slug'];
        $this->commit     = $config['commit'] ?? null;
        $this->extra      = $config['extra'] ?? [];
    }

    /**
     * @param array{
     *     file: string,
     *     slug: string,
     *     name?: string,
     *     prefix: string,
     *     textDomain: string,
     *     version: string,
     *     namespace: string,
     *     commit?: string|null,
     *     extra?: array<string, mixed>
     * } $config
     *
     * @throws \InvalidArgumentException If required config keys are missing.
     */
    public static function create(array $config): static
    {
        $required = [ 'file', 'slug', 'prefix', 'textDomain', 'version', 'namespace' ];
        $missing  = array_diff($required, array_keys($config));

        if (! empty($missing)) {
            throw new \InvalidArgumentException(
                sprintf('Missing required config keys: %s', implode(', ', $missing))
            );
        }

        return new static($config);
    }

    /**
     * Create the canonical context shared by every plugin lifecycle entry point.
     */
    public static function forPluginFile(string $pluginFile): static
    {
        return static::create([
            'file'       => $pluginFile,
            'slug'       => 'my-plugin',
            'name'       => 'My Plugin',
            'prefix'     => 'myplugin_',
            'textDomain' => 'my-plugin',
            'version'    => self::versionFromPluginFile($pluginFile),
            'namespace'  => 'MyPlugin',
        ]);
    }

    private static function versionFromPluginFile(string $pluginFile): string
    {
        if (! is_readable($pluginFile)) {
            return '0.0.0';
        }

        $header = file_get_contents($pluginFile, false, null, 0, 8192);

        if (! is_string($header)) {
            return '0.0.0';
        }

        return preg_match('/^[ \t\/*#@]*Version:\s*(.+)$/mi', $header, $matches)
            ? trim((string) $matches[1])
            : '0.0.0';
    }

    public function name(): string
    {
        return $this->name;
    }

    public function config(): ConfigRepository
    {
        if ($this->configRepo === null) {
            $items = [];

            $uiConfig = $this->path('config/ui.php');
            if (file_exists($uiConfig)) {
                $items['ui'] = require $uiConfig;
            }

            $appConfig = $this->path('config/app.php');
            if (file_exists($appConfig)) {
                $items = array_merge($items, require $appConfig);
            }

            $this->configRepo = new ConfigRepository($items);
        }

        return $this->configRepo;
    }

    public function slug(): string
    {
        return $this->slug;
    }

    public function prefix(): string
    {
        return $this->prefix;
    }

    public function textDomain(): string
    {
        return $this->textDomain;
    }

    public function version(): string
    {
        return $this->version;
    }

    public function namespace(): string
    {
        return $this->namespace;
    }

    public function commit(): ?string
    {
        return $this->commit;
    }

    public function extra(string $key, mixed $default = null): mixed
    {
        return $this->extra[ $key ] ?? $default;
    }

    /** @return array<string, mixed> */
    public function allExtra(): array
    {
        return $this->extra;
    }

    public function file(): string
    {
        return $this->file;
    }

    public function path(string $relativePath = ''): string
    {
        if ($this->basePath === null) {
            $this->basePath = plugin_dir_path($this->file);
        }

        return $relativePath === ''
            ? $this->basePath
            : $this->basePath . ltrim($relativePath, '/\\');
    }

    public function url(string $relativePath = ''): string
    {
        if ($this->baseUrl === null) {
            $this->baseUrl = plugin_dir_url($this->file);
        }

        return $relativePath === ''
            ? $this->baseUrl
            : $this->baseUrl . ltrim($relativePath, '/');
    }

    public function hook(string $name): string
    {
        return $this->prefix . $name;
    }

    public function optionKey(string $key): string
    {
        return $this->prefix . $key;
    }

    public function transientKey(string $key): string
    {
        return $this->prefix . $key;
    }

    public function cronHook(string $name): string
    {
        return $this->prefix . $name;
    }

    public function tableName(string $name, string $scope = 'site'): string
    {
        global $wpdb;

        $wpPrefix = ($scope === 'network' && isset($wpdb->base_prefix))
            ? $wpdb->base_prefix
            : $wpdb->prefix;

        return $wpPrefix . $this->prefix . $name;
    }

    public function metaKey(string $key): string
    {
        return '_' . $this->prefix . $key;
    }

    public function assetHandle(string $handle): string
    {
        return $this->slug . '-' . $handle;
    }
}
