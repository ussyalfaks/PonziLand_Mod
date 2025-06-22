import { getNetworks, startSwap } from '$lib/server/layerswap';
import { error, isRedirect, redirect } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';

const ssr = true;

export const load: PageServerLoad = async ({ params }) => {
  const networks = await getNetworks();

  if (networks.error) {
    throw new Error('Networks not found');
  }

  return { networks: networks.data };
};

export const actions = {
  default: async ({ request }) => {
    // Create the swap, and redirect to the swap execute page
    const formData = await request.formData();

    const destinationAddress = formData.get('destination_address') as string;
    const amount = Number(formData.get('amount'));
    const sourceNetwork = formData.get('source_network') as string;
    const sourceToken = formData.get('source_token') as string;

    try {
      const swap = await startSwap(
        sourceNetwork,
        sourceToken,
        destinationAddress,
        amount,
      );

      if (!swap?.data) {
        throw new Error('Failed to start swap');
      }

      return redirect(302, '/ramp/' + swap.data?.swap?.id);
    } catch (e) {
      if (isRedirect(e)) {
        throw e;
      }
      console.error('Error starting swap:', e);
      return error(500, 'Failed to start swap');
    }
  },
} satisfies Actions;
