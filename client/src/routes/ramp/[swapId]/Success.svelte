<script>
  import Button from '$lib/components/ui/button/button.svelte';
  import { Card } from '$lib/components/ui/card';
</script>

<h1 class="text-3xl text-center">Your swap has been completed!</h1>

<p class="mt-2 text-xl">
  You can now use the cartridge controller to access the game!
</p>

<div class="flex justify-center">
  <a href="/game">
    <Button>Play</Button>
  </a>
</div>
