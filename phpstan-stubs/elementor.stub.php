<?php

declare( strict_types=1 );

namespace Elementor;

/** PHPStan-only declarations for the optional Elementor dependency. */
abstract class Widget_Base {
	public function __construct( array $data = [], $args = null ) {
	}

	abstract public function get_name(): string;

	abstract public function get_title(): string;

	/** @return string[] */
	abstract public function get_categories(): array;

	protected function start_controls_section( string $id, array $args = [] ): void {
	}

	protected function add_control( string $id, array $args = [] ): void {
	}

	protected function end_controls_section(): void {
	}

	/** @return array<string, mixed> */
	protected function get_settings_for_display( ?string $setting = null ): array {
		return [];
	}
}

final class Controls_Manager {
	public const SELECT = 'select';
	public const TEXT = 'text';
}
