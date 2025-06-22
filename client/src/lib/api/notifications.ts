import type { Client } from '$lib/contexts/client.svelte';
import { ModelsMapping, type SchemaType } from '$lib/models.gen';
import { ToriiQueryBuilder, type ParsedEntity } from '@dojoengine/sdk';

// Fetch the data from torii
function getQuery(pagination?: { cursor?: string; size: number }) {
  let base = new ToriiQueryBuilder();
  if (pagination?.cursor) {
    base.withCursor(pagination.cursor);
  }

  if (pagination?.size) {
    base.withLimit(pagination.size);
    base.withDirection('Forward');
  }

  return (
    base
        .addEntityModel(ModelsMapping.AuctionFinishedEvent)
        .addEntityModel(ModelsMapping.LandBoughtEvent)
        .addEntityModel(ModelsMapping.LandNukedEvent)
        .addEntityModel(ModelsMapping.NewAuctionEvent)
        .addEntityModel(ModelsMapping.AddressAuthorizedEvent)
        .addEntityModel(ModelsMapping.AddressRemovedEvent)
        .addEntityModel(ModelsMapping.VerifierUpdatedEvent)
      .includeHashedKeys()
  );
}

export async function setupNotificationsSubscription(
  client: Client,
  callback: (entities: ParsedEntity<SchemaType>[]) => void,
) {
  const initialEntities: ParsedEntity<SchemaType>[] = [];
  const subscribeResponse = await client.subscribeEntityQuery({
    query: getQuery(),
    callback: (result) => {
      if (result.error) {
        console.error(result.error);
      } else {
        callback(result.data);
      }
    },
  });
  let data = subscribeResponse[0];

  initialEntities.push(...data.getItems());

  // Continue while we get data
  while (data.cursor != undefined) {
    // Make a new request with the next page
    let query = data.getNextQuery(getQuery());
    data = await client.getEntities({
      query: query,
    });

    initialEntities.push(...data.getItems());
  }

  return {
    initialEntities: initialEntities,
    subscription: subscribeResponse[1],
  };
} 