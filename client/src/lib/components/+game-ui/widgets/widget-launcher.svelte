<script lang="ts">
  import { Button } from '$lib/components/ui/button';
  import { widgetsStore } from '$lib/stores/widgets.store';
  import { availableWidgets } from './widgets.config';
  import { PUBLIC_SOCIALINK_URL } from '$env/static/public';
  import accountDataProvider, { setup } from '$lib/account.svelte';
  import { onMount } from 'svelte';

  let isVisible = $state(true);
  let url = $derived(
    `${PUBLIC_SOCIALINK_URL}/api/user/${accountDataProvider.address}/team/info`,
  );

  function addWidget(widgetType: string) {
    const widget = availableWidgets.find((w) => w.type === widgetType);
    if (!widget) return;

    // Check if widget already exists
    if ($widgetsStore[widget.id]) {
      if ($widgetsStore[widget.id].isOpen) {
        widgetsStore.updateWidget(widget.id, { isOpen: false });
      } else {
        widgetsStore.updateWidget(widget.id, { isOpen: true });
      }
      return;
    }

    // Add new widget
    widgetsStore.addWidget({
      id: widget.id,
      type: widget.type,
      position: { x: 300, y: 100 }, // Default position
      isMinimized: false,
      isOpen: true,
    });
  }

  onMount(async () => {
    try {
      const response = await fetch(url);
      const data = await response.json();
      if (data.team === null) {
        addWidget('guild');
      }
    } catch (error) {
      console.error('Failed to fetch team info:', error);
    }
  });
</script>

<div
  class="fixed bottom-2 left-2 flex gap-2 items-center"
  style="pointer-events: all;"
>
  {#if isVisible}
    {#each availableWidgets as widget}
      <Button
        class="w-24 h-24 flex flex-col gap-1"
        onclick={() => addWidget(widget.type)}
      >
        <img src={widget.icon} class="w-16 h-14" alt="" />
        <div class="font-ponzi-number stroke-3d-black text-[11px]">
          {widget.label}
        </div>
      </Button>
    {/each}
  {/if}

  <Button
    class="h-24 flex items-center justify-center p-2"
    onclick={() => (isVisible = !isVisible)}
  >
    {#if isVisible}
      <svg
        class="w-14 h-14"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path
          d="M15 18L9 12L15 6"
          stroke="#8B4513"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    {:else}
      <svg
        class="w-14 h-14"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path
          d="M9 18L15 12L9 6"
          stroke="#8B4513"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    {/if}
  </Button>
</div>
