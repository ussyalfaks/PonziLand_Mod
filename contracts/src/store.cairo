use dojo::world::{WorldStorage};
use dojo::model::{ModelStorage, ModelValueStorage};

use ponzi_land::models::land::{Land, PoolKey, LandStake};
use ponzi_land::models::auction::Auction;
use starknet::contract_address::ContractAddressZeroable;

#[derive(Copy, Drop)]
struct Store {
    world: WorldStorage,
}

#[generate_trait]
impl StoreImpl of StoreTrait {
    #[inline(always)]
    fn new(world: WorldStorage) -> Store {
        Store { world }
    }

    // Getter
    #[inline(always)]
    fn land(self: Store, land_location: u16) -> Land {
        self.world.read_model(land_location)
    }

    #[inline(always)]
    fn land_stake(self: Store, land_location: u16) -> LandStake {
        self.world.read_model(land_location)
    }

    #[inline(always)]
    fn auction(self: Store, land_location: u16) -> Auction {
        self.world.read_model(land_location)
    }

    // Setter
    #[inline(always)]
    fn set_land(mut self: Store, land: Land) {
        self.world.write_model(@land);
    }

    #[inline(always)]
    fn set_land_stake(mut self: Store, land_stake: LandStake) {
        self.world.write_model(@land_stake);
    }

    #[inline(always)]
    fn set_auction(mut self: Store, auction: Auction) {
        self.world.write_model(@auction);
    }

    // Deleter
    #[inline(always)]
    fn delete_land(mut self: Store, mut land: Land) {
        //Red: Attempt to see if it is still an issue with torii:
        self.world.erase_model(@land);
    }
}
