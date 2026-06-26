<?php

declare(strict_types=1);

/**
 * PHPStan-only declarations for optional WooCommerce admin field helpers.
 *
 * WooCommerce defines these functions at runtime in wp-admin contexts. Keeping
 * them in a stub avoids loading WooCommerce during static analysis.
 */
function woocommerce_wp_checkbox(array $field): void
{
}

function woocommerce_wp_textarea_input(array $field): void
{
}

function woocommerce_wp_text_input(array $field): void
{
}
