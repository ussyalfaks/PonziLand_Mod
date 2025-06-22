<script lang="ts">
  import { onMount } from 'svelte';
  import { useClient } from '$lib/contexts/client.svelte';
  import { setupNotificationsSubscription } from '$lib/api/notifications';
  import type { ParsedEntity } from '@dojoengine/sdk';
  import type { SchemaType } from '$lib/models.gen';

  let notifications: ParsedEntity<SchemaType>[] = [];
  let subscription: any;

  onMount(() => {
    const client = useClient();
    if (!client) return;

    let sub: any;

    setupNotificationsSubscription(client, (newNotifications) => {
      notifications = [...notifications, ...newNotifications];
    }).then(response => {
        notifications = response.initialEntities;
        sub = response.subscription;
    });

    return () => {
      // Unsubscribe when the component is destroyed
      if (sub) {
        sub.cancel();
      }
    };
  });
</script>

<div class="flex flex-col gap-2 overflow-y-auto p-4">
  {#each notifications as notification}
    <div class="p-2 bg-gray-800 rounded">
      <p class="text-sm">{JSON.stringify(notification, null, 2)}</p>
    </div>
  {/each}
</div>

<style>
  /* Scoped styles (Tailwind supported) */
</style> 