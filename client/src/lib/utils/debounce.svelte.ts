/**
 * Debounce code is taken from:
 * https://github.com/svelte-librarian/sv-use/blob/main/packages/core/src/reactivity/debounce/index.svelte.ts
 *
 * Copyright (c) 2024 Sajidur Rahman
 * Licenced under MIT
 */

import { untrack } from 'svelte';

type DebounceOptions = {
  /**
   * The delay in milliseconds before updating the state.
   * @default 1000
   */
  delay?: number;
};

/**
 * Debounces the update of the value after a delay.
 * @param initial The reactive value as a getter.
 * @param options Additional options to customize the behavior.
 * @see https://svelte-librarian.github.io/sv-use/docs/core/reactivity/debounce
 */
export function debounce<T>(value: () => T, options: DebounceOptions = {}) {
  const { delay = 1000 } = options;

  let timeout: number;
  const _state = $state<{ current: T | undefined }>({ current: undefined });

  $effect(() => {
    value();

    if (timeout) {
      clearTimeout(timeout);
    }

    untrack(() => {
      timeout = setTimeout(() => {
        _state.current = value();
      }, delay) as unknown as number;
    });

    return () => {
      clearTimeout(timeout);
    };
  });

  return _state;
}
