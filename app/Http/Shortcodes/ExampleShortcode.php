<?php

declare(strict_types=1);

namespace MyPlugin\Http\Shortcodes;

use WPZylos\Framework\Views\JsMount;
use WPZylos\Framework\Core\Contracts\ContextInterface;

class ExampleShortcode
{
    private ContextInterface $context;
    private JsMount $mount;

    public function __construct(ContextInterface $context, JsMount $mount)
    {
        $this->context = $context;
        $this->mount = $mount;
    }

    public function register(): void
    {
        add_shortcode('myplugin_widget', [$this, 'render']);
    }

    public function render(array $atts = []): string
    {
        $atts = shortcode_atts(['id' => 0, 'title' => ''], $atts);

        return $this->mount->frontendMount('myplugin-widget-' . $atts['id'], [
            'id' => (int) $atts['id'],
            'title' => sanitize_text_field($atts['title']),
        ]);
    }
}
