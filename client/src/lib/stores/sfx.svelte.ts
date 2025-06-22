import { createAudioStore } from '$lib/stores/AudioStore';
const sounds = {
  click: '/sfx/PL_ButtonClick2.wav',
  buy: '/sfx/PL_BuildingBuy.wav',
  claim: '/sfx/PL_Claim1.wav',
  biomeSelect: '/sfx/PL_BiomeSelect1.wav',
  hover: '/sfx/PL_Hover1.wav',
  launchGame: '/sfx/PL_LaunchGame.wav',
  nuke: '/sfx/PL_Nuke1.wav',
  coin1: '/sfx/PL_Coin.wav',
  swapDone: '/sfx/PL_SwapDone.wav',
  OnAuction: '/sfx/PL_AuctionLand.wav',
  EmptyLand: '/sfx/PL_EmptyLand.wav',
};

export let gameSounds = $state(createAudioStore(sounds));
