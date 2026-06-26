<?php

declare(strict_types=1);

/**
 * PHP-Scoper configuration.
 *
 * Prefixes vendor/framework namespaces for multi-plugin isolation while keeping
 * the plugin's own namespace and WordPress integration symbols stable.
 *
 * @see https://github.com/humbug/php-scoper
 */

use Isolated\Symfony\Component\Finder\Finder;

$pluginSlug = 'my_plugin';
$buildHash  = trim(shell_exec('git rev-parse --short HEAD 2>/dev/null') ?? '');

if (empty($buildHash)) {
    $buildHash = substr(md5((string) time()), 0, 8);
}

$prefix = "WPZylosScoped\\{$pluginSlug}_{$buildHash}";

return [
    'prefix' => $prefix,

    'finders' => [
        Finder::create()
            ->files()
            ->ignoreVCS(true)
            ->notName('/LICENSE|.*\\.md|.*\\.dist|Makefile/')
            ->exclude([
                'tests',
                'Tests',
                'docs',
                'doc',
                'node_modules',
                'resources',
                'dist',
                'build',
                '.git',
                '.github',
                'test',
                'test_old',
                'vendor-bin',
                'humbug',
            ])
            ->in([
                'vendor',
                'app',
                'bootstrap',
                'config',
                'routes',
            ]),
    ],

    'exclude-files' => [
        'my-plugin.php',
        'uninstall.php',
    ],

    'exclude-namespaces' => [
        'MyPlugin',
        'WP_CLI',
        'Elementor',
        'Composer',
    ],

    'exclude-classes' => [
        'WP_Error',
        'WP_Query',
        'WP_User',
        'WP_Post',
        'WP_Term',
        'WP_REST_Request',
        'WP_REST_Response',
        'wpdb',
        'Walker',
        'WP_Widget',
    ],

    'exclude-functions' => [
        'add_action',
        'add_filter',
        'do_action',
        'apply_filters',
        'remove_action',
        'remove_filter',
        'has_action',
        'has_filter',
        'get_option',
        'update_option',
        'delete_option',
        'add_option',
        'get_transient',
        'set_transient',
        'delete_transient',
        '__',
        '_e',
        '_n',
        '_x',
        'esc_html__',
        'esc_html_e',
        'esc_attr__',
        'esc_attr_e',
        'esc_html',
        'esc_attr',
        'esc_url',
        'esc_url_raw',
        'esc_js',
        'wp_kses',
        'wp_kses_post',
        'wp_kses_data',
        'sanitize_text_field',
        'sanitize_textarea_field',
        'sanitize_email',
        'sanitize_title',
        'sanitize_key',
        'sanitize_file_name',
        'sanitize_hex_color',
        'absint',
        'wp_create_nonce',
        'wp_verify_nonce',
        'wp_nonce_field',
        'wp_nonce_url',
        'check_admin_referer',
        'check_ajax_referer',
        'current_user_can',
        'user_can',
        'get_current_user_id',
        'is_user_logged_in',
        'register_activation_hook',
        'register_deactivation_hook',
        'register_uninstall_hook',
        'plugin_dir_path',
        'plugin_dir_url',
        'plugin_basename',
        'wp_upload_dir',
        'wp_mkdir_p',
        'flush_rewrite_rules',
        'add_rewrite_rule',
        'wp_die',
        'is_admin',
        'get_current_screen',
        'is_multisite',
        'wp_doing_ajax',
        'wp_doing_cron',
        'home_url',
        'add_query_arg',
        'wp_unslash',
        'wp_strip_all_tags',
        'wp_parse_url',
        'wp_date',
        'get_posts',
        'get_post_meta',
        'update_post_meta',
        'delete_post_meta',
        'get_permalink',
        'get_the_title',
        'get_the_post_thumbnail_url',
        'get_object_taxonomies',
        'has_term',
        'register_block_type',
        'wp_register_script',
        'wp_enqueue_script',
        'wp_add_inline_script',
        'wp_register_style',
        'wp_enqueue_style',
        'wp_add_inline_style',
        'wp_set_script_translations',
        'wp_json_encode',
        'vc_map',
        'wc_get_product',
        'wc_get_page_permalink',
        'wc_placeholder_img_src',
        'woocommerce_wp_checkbox',
        'woocommerce_wp_text_input',
    ],

    'exclude-constants' => [
        'ABSPATH',
        'WPINC',
        'WP_CONTENT_DIR',
        'WP_CONTENT_URL',
        'WP_PLUGIN_DIR',
        'WP_PLUGIN_URL',
        'WP_DEBUG',
        'WP_DEBUG_LOG',
        'DOING_AJAX',
        'DOING_CRON',
        'REST_REQUEST',
        'XMLRPC_REQUEST',
        'WP_CLI',
    ],

    'patchers' => [
        // Fix string class references if needed.
    ],

    'expose-global-constants' => true,
    'expose-global-classes'   => true,
    'expose-global-functions' => true,
];
