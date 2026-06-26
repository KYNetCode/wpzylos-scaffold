<?php

/**
 * UI configuration.
 *
 * Controls CSS prefixing for DaisyUI / Tailwind scoped styles.
 * The css_prefix must match the DaisyUI prefix defined in resources/css/admin.css.
 *
 * Scaffold placeholder: run `./scaffold.ps1 init` (Windows) or
 * `./scaffold.sh init` (Linux/Mac) to replace __CSS_PREFIX__ with
 * your actual plugin prefix automatically.
 *
 * @package MyPlugin
 */

return [
    /**
     * CSS class prefix used for scoped UI classes.
     *
     * This value drives two separate prefix systems:
     *   - Tailwind CSS v4 utilities use the no-hyphen form: __CSS_PREFIX_NOHYPHEN__:
     *   - DaisyUI components use the hyphen form: __CSS_PREFIX__btn
     *   - Admin styles are scoped under: #__CSS_PREFIX_NOHYPHEN__-admin
     */
    'css_prefix' => '__CSS_PREFIX__',
];
