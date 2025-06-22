<script lang="ts">
  import { onMount } from 'svelte';
  import { landStore } from '$lib/stores/store.svelte';
  import { moveCameraToLocation } from '$lib/stores/camera.store';
  import { GRID_SIZE } from '$lib/const';
  import type { BaseLand } from '$lib/api/land';
  import { EmptyLand } from '$lib/api/land';
  import { BuildingLand } from '$lib/api/land/building_land';

  let lands: BaseLand[] = [];
  let grid: BaseLand[][] = Array(GRID_SIZE).fill(null).map(() => Array(GRID_SIZE).fill(new EmptyLand({x:0, y:0})));

  onMount(() => {
    const unsubscribe = landStore.getAllLands().subscribe(allLands => {
      lands = allLands;
      // Create a 2D grid for easier rendering
      grid = Array(GRID_SIZE).fill(null).map(() => Array(GRID_SIZE).fill(new EmptyLand({x:0, y:0})));
      for (const land of lands) {
        if (land.location) {
          grid[land.location.y][land.location.x] = land;
        }
      }
    });

    return () => {
      unsubscribe();
    };
  });

  function handleCellClick(land: BaseLand) {
    if (land.location) {
      const locationId = land.location.y * GRID_SIZE + land.location.x;
      moveCameraToLocation(locationId, 1); // Zoom in
    }
  }

  function getLandColor(land: BaseLand): string {
    if (land instanceof BuildingLand) {
        return 'bg-blue-500'; // Owned land
    }
    return 'bg-gray-700'; // Empty land
  }
</script>

<div class="grid h-full w-full" style="grid-template-columns: repeat({GRID_SIZE}, 1fr);">
  {#each grid as row, y}
    {#each row as land, x}
      <div
        class="w-full h-full border border-gray-900 {getLandColor(land)}"
        on:click={() => handleCellClick(land)}
        title={`(${x}, ${y})`}
      ></div>
    {/each}
  {/each}
</div>

<style>
  /* Scoped styles (Tailwind supported) */
</style> 