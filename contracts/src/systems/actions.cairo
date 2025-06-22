use starknet::ContractAddress;

use dojo::world::WorldStorage;
use ponzi_land::models::land::{Land, LandStake};
use ponzi_land::models::auction::Auction;
use ponzi_land::utils::common_strucs::{TokenInfo, ClaimInfo, LandYieldInfo, LandOrAuction};

// define the interface
#[starknet::interface]
trait IActions<T> {
    fn bid(
        ref self: T,
        land_location: u16,
        token_for_sale: ContractAddress,
        sell_price: u256,
        amount_to_stake: u256,
    );
    fn buy(
        ref self: T,
        land_location: u16,
        token_for_sale: ContractAddress,
        sell_price: u256,
        amount_to_stake: u256,
    );

    fn recreate_auction(ref self: T, land_location: u16);

    fn claim(ref self: T, land_location: u16);

    fn claim_all(ref self: T, land_locations: Array<u16>);

    fn increase_price(ref self: T, land_location: u16, new_price: u256);

    fn increase_stake(ref self: T, land_location: u16, amount_to_stake: u256);

    fn level_up(ref self: T, land_location: u16) -> bool;

    fn reimburse_stakes(ref self: T);

    fn get_land(self: @T, land_location: u16) -> (Land, LandStake);
    fn get_pending_taxes_for_land(
        self: @T, land_location: u16, owner: ContractAddress,
    ) -> Array<TokenInfo>;
    fn get_current_auction_price(self: @T, land_location: u16) -> u256;
    fn get_next_claim_info(self: @T, land_location: u16) -> Array<ClaimInfo>;
    fn get_neighbors_yield(self: @T, land_location: u16) -> LandYieldInfo;
    fn get_active_auctions(self: @T) -> u8;
    fn get_auction(self: @T, land_location: u16) -> Auction;
    fn get_time_to_nuke(self: @T, land_location: u16) -> u64;
    fn get_unclaimed_taxes_per_neighbor(self: @T, land_location: u16) -> u256;
    // returns (pending_taxes, unclaimed_taxes)
    fn get_claimable_taxes_for_land(
        self: @T, land_location: u16, owner: ContractAddress,
    ) -> (Array<TokenInfo>, Array<TokenInfo>);
    fn get_game_speed(self: @T) -> u64;
    fn get_neighbors(self: @T, land_location: u16) -> Array<LandOrAuction>;

    fn set_main_token(ref self: T, token_address: ContractAddress) -> ();
}

// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{IActions, WorldStorage};

    use core::nullable::{Nullable, NullableTrait, match_nullable, FromNullableResult};
    use core::dict::{Felt252Dict, Felt252DictTrait, Felt252DictEntryTrait};

    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Vec, VecTrait,
        MutableVecTrait,
    };
    use dojo::model::{ModelStorage, ModelValueStorage};
    use dojo::event::EventStorage;
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};

    use ponzi_land::systems::auth::{IAuthDispatcher, IAuthDispatcherTrait};

    use ponzi_land::systems::token_registry::{
        ITokenRegistryDispatcher, ITokenRegistryDispatcherTrait,
    };

    use ponzi_land::models::land::{Land, LandStake, LandTrait, Level, PoolKeyConversion, PoolKey};
    use ponzi_land::models::auction::{Auction, AuctionTrait};

    use ponzi_land::components::stake::StakeComponent;
    use ponzi_land::components::taxes::TaxesComponent;
    use ponzi_land::components::payable::PayableComponent;

    use ponzi_land::utils::common_strucs::{
        TokenInfo, ClaimInfo, YieldInfo, LandYieldInfo, LandWithTaxes, LandOrAuction,
    };
    use ponzi_land::utils::get_neighbors::{
        get_land_neighbors, get_average_price, process_neighbors_of_neighbors,
    };
    use ponzi_land::utils::spiral::{get_next_position, SpiralState};
    use ponzi_land::utils::level_up::{calculate_new_level};
    use ponzi_land::utils::stake::{calculate_refund_amount};

    use ponzi_land::helpers::coord::{
        is_valid_position, up, down, left, right, max_neighbors, index_to_position,
        position_to_index, up_left, up_right, down_left, down_right, get_all_neighbors,
    };
    use ponzi_land::helpers::taxes::{
        get_taxes_per_neighbor, get_tax_rate_per_neighbor, get_time_to_nuke,
    };
    use ponzi_land::helpers::circle_expansion::{
        get_circle_land_position, get_random_index, lands_per_section, generate_circle,
        is_section_completed, get_random_available_index,
    };

    use ponzi_land::consts::{
        TAX_RATE, BASE_TIME, TIME_SPEED, MAX_AUCTIONS, MAX_AUCTIONS_FROM_BID, DECAY_RATE,
        FLOOR_PRICE, LIQUIDITY_SAFETY_MULTIPLIER, MIN_AUCTION_PRICE, GRID_WIDTH,
        FACTOR_FOR_SELL_PRICE, CENTER_LOCATION,
    };
    use ponzi_land::store::{Store, StoreTrait};
    use ponzi_land::interfaces::systems::{SystemsTrait};

    component!(path: PayableComponent, storage: payable, event: PayableEvent);
    impl PayableInternalImpl = PayableComponent::PayableImpl<ContractState>;

    component!(path: StakeComponent, storage: stake, event: StakeEvent);
    impl StakeInternalImpl = StakeComponent::InternalImpl<ContractState>;

    component!(path: TaxesComponent, storage: taxes, event: TaxesEvent);
    impl TaxesInternalImpl = TaxesComponent::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        PayableEvent: PayableComponent::Event,
        #[flat]
        StakeEvent: StakeComponent::Event,
        #[flat]
        TaxesEvent: TaxesComponent::Event,
    }

    //events

    #[derive(Drop, Serde)]
    #[dojo::event]
    pub struct LandNukedEvent {
        #[key]
        owner_nuked: ContractAddress,
        land_location: u16,
    }


    #[derive(Drop, Serde)]
    #[dojo::event]
    pub struct LandBoughtEvent {
        #[key]
        buyer: ContractAddress,
        #[key]
        land_location: u16,
        sold_price: u256,
        seller: ContractAddress,
        token_used: ContractAddress,
    }


    #[derive(Drop, Serde)]
    #[dojo::event]
    pub struct NewAuctionEvent {
        #[key]
        land_location: u16,
        start_price: u256,
        floor_price: u256,
    }

    #[derive(Drop, Serde)]
    #[dojo::event]
    pub struct AuctionFinishedEvent {
        #[key]
        land_location: u16,
        buyer: ContractAddress,
        final_price: u256,
    }

    #[derive(Drop, Serde)]
    #[dojo::event]
    pub struct AddStakeEvent {
        #[key]
        land_location: u16,
        new_stake_amount: u256,
        owner: ContractAddress,
    }


    mod errors {
        const ERC20_PAY_FOR_BUY_FAILED: felt252 = 'ERC20: pay for buy failed';
        const ERC20_PAY_FOR_BID_FAILED: felt252 = 'ERC20: pay for bid failed';
        const ERC20_VALIDATE_AMOUNT_BUY: felt252 = 'validate amount for buy failed';
        const ERC20_VALIDATE_AMOUNT_BID: felt252 = 'validate amount for bid failed';
    }

    // Storage
    #[storage]
    struct Storage {
        #[substorage(v0)]
        payable: PayableComponent::Storage,
        #[substorage(v0)]
        stake: StakeComponent::Storage,
        #[substorage(v0)]
        taxes: TaxesComponent::Storage,
        active_auctions: u8,
        main_currency: ContractAddress,
        ekubo_dispatcher: ICoreDispatcher,
        active_auction_queue: Map<u16, bool>,
        staked_lands: Map<u16, bool>, // New storage variable to track staked lands
        used_lands_in_circle: Map<(u16, u8), Vec<u16>>,
        current_circle: u16,
        current_section: Map<u16, u8>,
        completed_lands_per_section: Map<(u16, u8), u16>,
    }

    fn dojo_init(
        ref self: ContractState,
        token_address: ContractAddress,
        start_price: u256,
        floor_price: u256,
        decay_rate: u16,
        ekubo_core_address: ContractAddress,
    ) {
        self.main_currency.write(token_address);
        self.ekubo_dispatcher.write(ICoreDispatcher { contract_address: ekubo_core_address });
        self.current_circle.write(1);
        self.current_section.write(1, 0);
        self.auction(CENTER_LOCATION, start_price, floor_price, decay_rate, false);
    }


    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn set_main_token(ref self: ContractState, token_address: ContractAddress) -> () {
            let mut world = self.world_default();
            assert(world.auth_dispatcher().get_owner() == get_caller_address(), 'not the owner');
            self.main_currency.write(token_address);
        }


        fn buy(
            ref self: ContractState,
            land_location: u16,
            token_for_sale: ContractAddress,
            sell_price: u256,
            amount_to_stake: u256,
        ) {
            assert(is_valid_position(land_location), 'Land location not valid');
            assert(sell_price > 0, 'sell_price > 0');
            assert(amount_to_stake > 0, 'amount_to_stake > 0');

            let mut world = self.world_default();
            let caller = get_caller_address();

            assert(
                world.auth_dispatcher().can_take_action(get_caller_address()),
                'action not permitted',
            );

            let mut store = StoreTrait::new(world);
            let land = store.land(land_location);

            assert(caller != land.owner, 'you already own this land');
            assert(land.owner != ContractAddressZeroable::zero(), 'must have a owner');

            world.token_registry_dispatcher().ensure_token_authorized(token_for_sale);

            let seller = land.owner;
            let sold_price = land.sell_price;
            let token_used = land.token_used;
            self.internal_claim(store, land);

            let validation_result = self.payable.validate(land.token_used, caller, land.sell_price);
            assert(validation_result.status, errors::ERC20_VALIDATE_AMOUNT_BUY);

            let transfer_status = self.payable.transfer_from(caller, land.owner, validation_result);
            assert(transfer_status, errors::ERC20_PAY_FOR_BUY_FAILED);

            self.stake._refund(store, land);

            self
                .finalize_land_purchase(
                    store, land_location, token_for_sale, sell_price, amount_to_stake, caller,
                );

            store
                .world
                .emit_event(
                    @LandBoughtEvent {
                        buyer: caller, land_location: land.location, sold_price, seller, token_used,
                    },
                );
        }


        fn claim(ref self: ContractState, land_location: u16) {
            assert(is_valid_position(land_location), 'Land location not valid');
            let caller = get_caller_address();
            let mut world = self.world_default();
            assert(world.auth_dispatcher().can_take_action(caller), 'action not permitted');
            let mut store = StoreTrait::new(world);

            let land = store.land(land_location);
            assert(land.owner == caller, 'not the owner');

            self.internal_claim(store, land);
        }

        fn claim_all(ref self: ContractState, land_locations: Array<u16>) {
            let caller = get_caller_address();
            let mut world = self.world_default();
            assert(world.auth_dispatcher().can_take_action(caller), 'action not permitted');
            let mut store = StoreTrait::new(world);

            for land_location in land_locations {
                if !self.active_auction_queue.read(land_location) {
                    assert(is_valid_position(land_location), 'Land location not valid');
                    let land = store.land(land_location);
                    if land.owner != caller {
                        continue;
                    }
                    self.internal_claim(store, land);
                }
            };
        }

        fn bid(
            ref self: ContractState,
            land_location: u16,
            token_for_sale: ContractAddress,
            sell_price: u256,
            amount_to_stake: u256,
        ) {
            let mut world = self.world_default();

            let caller = get_caller_address();
            assert(world.auth_dispatcher().can_take_action(caller), 'action not permitted');

            let mut store = StoreTrait::new(world);

            let mut land = store.land(land_location);

            assert(is_valid_position(land_location), 'Land location not valid');
            assert(land.owner == ContractAddressZeroable::zero(), 'must be without owner');
            assert(sell_price > 0, 'sell_price > 0');
            assert(amount_to_stake > 0, 'amount_to_stake > 0');

            // Validate that the token is authorized to be used
            world.token_registry_dispatcher().ensure_token_authorized(token_for_sale);

            //auction part

            //Validate if the land can be buyed because is an auction happening for that land
            let mut auction = store.auction(land_location);
            // Red: Why check the active auction queue?
            assert(self.active_auction_queue.read(land_location), 'auction not started');

            let current_price = auction.get_current_price_decay_rate();

            self.internal_claim(store, land);

            self
                .buy_from_bid(
                    store,
                    land,
                    token_for_sale,
                    sell_price,
                    current_price,
                    amount_to_stake,
                    caller,
                    auction,
                );
        }

        fn recreate_auction(ref self: ContractState, land_location: u16) {
            assert(is_valid_position(land_location), 'Land location not valid');
            let caller = get_caller_address();
            let mut world = self.world_default();
            let contract_owner = world.auth_dispatcher().get_owner();
            assert(contract_owner == caller, 'action not permitted');

            let mut store = StoreTrait::new(world);
            let mut land = store.land(land_location);
            assert(land.owner == ContractAddressZeroable::zero(), 'land must be without owner');
            store.delete_land(land);

            let sell_price = get_average_price(store, land_location);
            let sell_price = if sell_price > MIN_AUCTION_PRICE {
                sell_price
            } else {
                MIN_AUCTION_PRICE
            };

            self.auction(land_location, sell_price, FLOOR_PRICE, DECAY_RATE, true);
        }


        fn increase_price(ref self: ContractState, land_location: u16, new_price: u256) {
            assert(is_valid_position(land_location), 'Land location not valid');

            let mut world = self.world_default();
            let caller = get_caller_address();

            assert(world.auth_dispatcher().can_take_action(caller), 'action not permitted');

            let mut store = StoreTrait::new(world);

            let mut land = store.land(land_location);

            assert(land.owner == caller, 'not the owner');
            assert(new_price > land.sell_price, 'new_price != land.sell_price');

            land.sell_price = new_price;
            store.set_land(land);
        }

        fn increase_stake(ref self: ContractState, land_location: u16, amount_to_stake: u256) {
            assert(is_valid_position(land_location), 'Land location not valid');

            let mut world = self.world_default();
            let caller = get_caller_address();

            assert(world.auth_dispatcher().can_take_action(caller), 'action not permitted');

            let mut store = StoreTrait::new(world);

            let land = store.land(land_location);

            assert(land.owner == caller, 'not the owner');
            assert(amount_to_stake > 0, 'amount has to be > 0');
            let mut land_stake = store.land_stake(land.location);
            self.stake._add(amount_to_stake, land, land_stake, store);
            let new_stake_amount = land_stake.amount + amount_to_stake;
            store
                .world
                .emit_event(@AddStakeEvent { land_location, new_stake_amount, owner: caller })
        }

        fn level_up(ref self: ContractState, land_location: u16) -> bool {
            assert(is_valid_position(land_location), 'Land location not valid');

            let mut world = self.world_default();

            let caller = get_caller_address();
            assert(world.auth_dispatcher().can_take_action(caller), 'action not permitted');

            let mut store = StoreTrait::new(world);
            let mut land = store.land(land_location);

            assert(land.owner == caller, 'not the owner');

            let current_time = get_block_timestamp();
            let elapsed_time_since_buy = (current_time - land.block_date_bought)
                * TIME_SPEED.into();

            self.update_level(ref store, ref land, elapsed_time_since_buy)
        }

        fn reimburse_stakes(ref self: ContractState) {
            let mut world = self.world_default();
            assert(world.auth_dispatcher().get_owner() == get_caller_address(), 'not the owner');

            let mut store = StoreTrait::new(world);
            let mut active_lands: Array<Land> = ArrayTrait::new();

            let mut i: u16 = 0;
            loop {
                if i >= GRID_WIDTH * GRID_WIDTH {
                    break;
                }
                if self.staked_lands.read(i) {
                    let land = store.land(i);
                    let land_stake = store.land_stake(i);
                    if !land.owner.is_zero() && land_stake.amount > 0 {
                        active_lands.append(land);
                    }
                }
                i += 1;
            };

            self.stake._reimburse(store, active_lands.span());

            self._distribute_adjusted_taxes(active_lands);
        }


        //GETTERS FUNCTIONS

        fn get_pending_taxes_for_land(
            self: @ContractState, land_location: u16, owner: ContractAddress,
        ) -> Array<TokenInfo> {
            self.taxes._get_pending_taxes(owner, land_location)
        }

        fn get_land(self: @ContractState, land_location: u16) -> (Land, LandStake) {
            assert(is_valid_position(land_location), 'Land location not valid');
            let mut world = self.world_default();
            let store = StoreTrait::new(world);
            let land = store.land(land_location);
            let land_stake = store.land_stake(land_location);
            (land, land_stake)
        }


        fn get_current_auction_price(self: @ContractState, land_location: u16) -> u256 {
            assert(is_valid_position(land_location), 'Land location not valid');
            let mut world = self.world_default();
            let store = StoreTrait::new(world);
            let auction = store.auction(land_location);

            if auction.is_finished {
                return 0;
            }
            auction.get_current_price_decay_rate()
        }

        fn get_next_claim_info(self: @ContractState, land_location: u16) -> Array<ClaimInfo> {
            assert(is_valid_position(land_location), 'Land location not valid');
            let mut world = self.world_default();
            let store = StoreTrait::new(world);
            let land = store.land(land_location);

            let neighbors = get_land_neighbors(store, land.location);
            let mut claim_info: Array<ClaimInfo> = ArrayTrait::new();

            //TODO:see if we pass this to utils
            if neighbors.len() > 0 {
                for neighbor in neighbors {
                    let land_stake = store.land_stake(neighbor.location);
                    if land_stake.amount > 0 {
                        let tax_per_neighbor = self
                            .get_unclaimed_taxes_per_neighbor(neighbor.location);

                        let time_to_nuke = self.get_time_to_nuke(neighbor.location);

                        let claim_info_per_neighbor = ClaimInfo {
                            token_address: neighbor.token_used,
                            amount: tax_per_neighbor,
                            land_location: neighbor.location,
                            can_be_nuked: time_to_nuke == 0,
                        };
                        claim_info.append(claim_info_per_neighbor);
                    }
                }
            }
            claim_info
        }

        fn get_neighbors_yield(self: @ContractState, land_location: u16) -> LandYieldInfo {
            assert(is_valid_position(land_location), 'Land location not valid');
            let mut world = self.world_default();
            let store = StoreTrait::new(world);
            let land = store.land(land_location);
            let neighbors = get_land_neighbors(store, land.location);
            let neighbors_count = neighbors.len();

            let mut yield_info: Array<YieldInfo> = ArrayTrait::new();
            if neighbors_count > 0 {
                for neighbor in neighbors {
                    let land_stake = store.land_stake(neighbor.location);
                    if land_stake.amount > 0 {
                        let token = neighbor.token_used;
                        //TODO: WHY THIS???? remove or fix after playtest
                        let rate = TAX_RATE.into() * TIME_SPEED.into() / 8;
                        let rate_per_hour = get_tax_rate_per_neighbor(neighbor);
                        yield_info
                            .append(
                                YieldInfo {
                                    token,
                                    sell_price: neighbor.sell_price,
                                    percent_rate: rate,
                                    per_hour: rate_per_hour,
                                    location: neighbor.location,
                                },
                            );
                    }
                }
            }

            let time_to_nuke = self.get_time_to_nuke(land.location);
            LandYieldInfo { yield_info, remaining_stake_time: time_to_nuke.into() }
        }


        fn get_active_auctions(self: @ContractState) -> u8 {
            self.active_auctions.read()
        }

        fn get_auction(self: @ContractState, land_location: u16) -> Auction {
            assert(is_valid_position(land_location), 'Land location not valid');
            let mut world = self.world_default();
            let store = StoreTrait::new(world);
            store.auction(land_location)
        }

        fn get_time_to_nuke(self: @ContractState, land_location: u16) -> u64 {
            let mut world = self.world_default();
            let store = StoreTrait::new(world);
            let land = store.land(land_location);
            let land_stake = store.land_stake(land_location);
            let num_neighbors = get_land_neighbors(store, land.location).len();

            get_time_to_nuke(land, land_stake, num_neighbors.try_into().unwrap())
                .try_into()
                .unwrap()
        }

        fn get_unclaimed_taxes_per_neighbor(self: @ContractState, land_location: u16) -> u256 {
            let world = self.world_default();
            let store = StoreTrait::new(world);
            let land = store.land(land_location);
            let land_stake = store.land_stake(land_location);
            get_taxes_per_neighbor(land, land_stake)
        }

        fn get_claimable_taxes_for_land(
            self: @ContractState, land_location: u16, owner: ContractAddress,
        ) -> (Array<TokenInfo>, Array<TokenInfo>) {
            let world = self.world_default();
            let store = StoreTrait::new(world);

            let pending_taxes = self.get_pending_taxes_for_land(land_location, owner);

            let neighbors = get_land_neighbors(store, land_location);

            let mut unclaimed_taxes: Array<TokenInfo> = ArrayTrait::new();

            for neighbor in neighbors {
                let taxes_per_neighbor = self.get_unclaimed_taxes_per_neighbor(neighbor.location);
                let tax_info = TokenInfo {
                    token_address: neighbor.token_used, amount: taxes_per_neighbor,
                };
                unclaimed_taxes.append(tax_info);
            };

            (pending_taxes, unclaimed_taxes)
        }

        fn get_game_speed(self: @ContractState) -> u64 {
            TIME_SPEED.into()
        }

        fn get_neighbors(self: @ContractState, land_location: u16) -> Array<LandOrAuction> {
            let mut world = self.world_default();

            let neighbors = get_all_neighbors(land_location);

            let mut neighbors_array = ArrayTrait::new();

            for neighbor in neighbors {
                let maybe_auction: Auction = world.read_model(neighbor);
                let maybe_land: Land = world.read_model(neighbor);

                if maybe_auction.floor_price != 0 && maybe_auction.is_finished == false {
                    neighbors_array.append(LandOrAuction::Auction(maybe_auction));
                } else if maybe_land.sell_price != 0 {
                    neighbors_array.append(LandOrAuction::Land(maybe_land));
                } else {
                    neighbors_array.append(LandOrAuction::None);
                }
            };

            neighbors_array
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> WorldStorage {
            self.world(@"ponzi_land")
        }

        fn auction(
            ref self: ContractState,
            land_location: u16,
            start_price: u256,
            floor_price: u256,
            decay_rate: u16,
            is_from_nuke: bool,
        ) {
            assert(is_valid_position(land_location), 'Land location not valid');
            assert(start_price > 0, 'start_price > 0');
            assert(floor_price > 0, 'floor_price > 0');
            //we don't want generate an error if the auction is full
            if (!is_from_nuke && self.active_auctions.read() >= MAX_AUCTIONS) {
                return;
            }
            let mut world = self.world_default();
            let mut store = StoreTrait::new(world);
            let mut land = store.land(land_location);

            assert(land.owner == ContractAddressZeroable::zero(), 'must be without owner');
            let auction = AuctionTrait::new(
                land_location, start_price, floor_price, false, decay_rate,
            );

            store.set_auction(auction);
            self.active_auctions.write(self.active_auctions.read() + 1);
            self.active_auction_queue.write(land_location, true);
            land.sell_price = start_price;
            // land.token_used = LORDS_CURRENCY;
            land.token_used = self.main_currency.read();

            store.set_land(land);
            store.world.emit_event(@NewAuctionEvent { land_location, start_price, floor_price });
        }

        fn nuke(ref self: ContractState, land_location: u16, has_liquidity_requirements: bool) {
            let mut world = self.world_default();
            let mut store = StoreTrait::new(world);
            let mut land = store.land(land_location);
            let mut land_stake = store.land_stake(land.location);

            if !has_liquidity_requirements && land_stake.amount > 0 {
                self.stake._refund(store, land);
                land_stake = store.land_stake(land.location);
            }

            assert(land_stake.amount == 0, 'land not valid to nuke');

            let pending_taxes = self.get_pending_taxes_for_land(land.location, land.owner);
            if pending_taxes.len() != 0 {
                self.taxes._claim(pending_taxes, land.owner, land.location);
            }

            let owner_nuked = land.owner;
            store.delete_land(land);

            world.emit_event(@LandNukedEvent { owner_nuked, land_location });

            let sell_price = get_average_price(store, land_location);
            let sell_price = if sell_price > MIN_AUCTION_PRICE {
                sell_price
            } else {
                MIN_AUCTION_PRICE
            };

            self.auction(land_location, sell_price, FLOOR_PRICE, DECAY_RATE, true);
        }

        fn internal_claim(ref self: ContractState, mut store: Store, land: Land) {
            //generate taxes for each neighbor of claimer
            let neighbors = get_land_neighbors(store, land.location);
            let mut neighbors_dict = process_neighbors_of_neighbors(store, neighbors.clone());

            if neighbors.len() != 0 {
                for mut neighbor in neighbors {
                    let is_nuke = self
                        .taxes
                        ._calculate_and_distribute(store, neighbor, ref neighbors_dict);

                    let has_liquidity_requirements = self
                        .world_default()
                        .token_registry_dispatcher()
                        .is_token_authorized(neighbor.token_used);

                    if is_nuke || !has_liquidity_requirements {
                        self.nuke(neighbor.location, has_liquidity_requirements);
                    }
                };
            }

            //claim taxes for the land
            let taxes = self.get_pending_taxes_for_land(land.location, land.owner);
            self._claim_and_discount_taxes(taxes, land.owner, land.location);
        }

        fn buy_from_bid(
            ref self: ContractState,
            mut store: Store,
            mut land: Land,
            token_for_sale: ContractAddress,
            sell_price: u256,
            sold_at_price: u256,
            amount_to_stake: u256,
            caller: ContractAddress,
            mut auction: Auction,
        ) {
            let validation_result = self.payable.validate(land.token_used, caller, sold_at_price);
            assert(validation_result.status, errors::ERC20_VALIDATE_AMOUNT_BID);
            let pay_to_us_status = self.payable.pay_to_us(caller, validation_result);
            assert(pay_to_us_status, errors::ERC20_PAY_FOR_BID_FAILED);

            // Red: If we create a new trait here,
            // I don't think we need to create the land before.
            self
                .finalize_land_purchase(
                    store, land.location, token_for_sale, sell_price, amount_to_stake, caller,
                );
            self.staked_lands.write(land.location, true);

            auction.is_finished = true;
            auction.sold_at_price = Option::Some(sold_at_price);
            store.set_auction(auction);
            // Red: We're reading the active auctions here, and it's not going to change after that,
            // reuse it
            self.active_auctions.write(self.active_auctions.read() - 1);
            self.active_auction_queue.write(land.location, false);

            store
                .world
                .emit_event(
                    @AuctionFinishedEvent {
                        land_location: land.location,
                        buyer: caller,
                        final_price: auction.get_current_price_decay_rate(),
                    },
                );

            //initialize auction for neighbors
            //TODO:Token for sale has to be lords or the token that we choose
            //TODO:we have to define the correct decay rate

            // Math.max(sold_at_price * 10, auction.floor_price)
            // Red: ...reused here.
            if self.active_auctions.read() < MAX_AUCTIONS {
                let asking_price = sold_at_price * FACTOR_FOR_SELL_PRICE.into();
                let asking_price = if asking_price > MIN_AUCTION_PRICE {
                    sold_at_price
                } else {
                    MIN_AUCTION_PRICE
                };
                self.generate_new_auctions(asking_price)
            }
        }

        fn finalize_land_purchase(
            ref self: ContractState,
            mut store: Store,
            land_location: u16,
            token_for_sale: ContractAddress,
            sell_price: u256,
            amount_to_stake: u256,
            caller: ContractAddress,
        ) {
            let land = LandTrait::new(
                land_location, caller, token_for_sale, sell_price, get_block_timestamp(),
            );
            store.set_land(land);
            let mut land_stake = store.land_stake(land.location);
            self.stake._add(amount_to_stake, land, land_stake, store);
        }

        fn update_level(
            self: @ContractState, ref store: Store, ref land: Land, elapsed_time: u64,
        ) -> bool {
            let new_level = calculate_new_level(elapsed_time);

            if land.level != new_level {
                land.level = new_level;
                store.set_land(land);
                true
            } else {
                false
            }
        }

        fn check_liquidity_pool_requirements(
            self: @ContractState, sell_token: ContractAddress, sell_price: u256, pool_key: PoolKey,
        ) -> bool {
            let main_currency = self.main_currency.read();

            // We need to validate that the poolkey:
            // - Is valid (token0 < token1)
            // - Contains main_currency in one of its two tokens
            // - Contains sell_token in one of its two tokens

            let token0 = pool_key.token0;
            let token1 = pool_key.token1;

            if token0 != main_currency && token1 != main_currency {
                return false;
            }

            if token0 != sell_token && token1 != sell_token {
                return false;
            }

            if token0 == token1 {
                // We cannot create a liquidity pool between the same tokens,
                // so we always accept it
                return true;
            }

            let liquidity_pool: u128 = self
                .ekubo_dispatcher
                .read()
                .get_pool_liquidity(PoolKeyConversion::to_ekubo(pool_key));
            return (sell_price * LIQUIDITY_SAFETY_MULTIPLIER.into()) < liquidity_pool.into();
        }

        fn _claim_and_discount_taxes(
            ref self: ContractState, taxes: Array<TokenInfo>, owner: ContractAddress, location: u16,
        ) {
            if taxes.len() != 0 {
                self.stake._discount_total_stake(taxes.span());
                self.taxes._claim(taxes, owner, location);
            }
        }

        fn _distribute_adjusted_taxes(ref self: ContractState, active_lands: Array<Land>) {
            for land in active_lands.span() {
                let land = *land;
                let mut adjusted_taxes: Array<TokenInfo> = ArrayTrait::new();
                let taxes = self.get_pending_taxes_for_land(land.location, land.owner);
                for tax in taxes.span() {
                    let tax = *tax;
                    let token_ratio = self.stake._get_token_ratios(tax.token_address);
                    let adjuested_tax_amount = calculate_refund_amount(tax.amount, token_ratio);
                    adjusted_taxes
                        .append(
                            TokenInfo {
                                token_address: tax.token_address, amount: adjuested_tax_amount,
                            },
                        )
                };

                self._claim_and_discount_taxes(adjusted_taxes, land.owner, land.location);
            };
        }

        fn generate_new_auctions(ref self: ContractState, start_price: u256) {
            let active_auctions = self.active_auctions.read();
            let mut remaining_auctions = MAX_AUCTIONS - active_auctions;
            let mut i = 0;

            while i < MAX_AUCTIONS_FROM_BID && remaining_auctions > 0 {
                let new_auction_location = self.select_next_auction_location();
                self.auction(new_auction_location, start_price, FLOOR_PRICE, DECAY_RATE, false);
                i += 1;
                remaining_auctions -= 1;
            }
        }

        fn select_next_auction_location(ref self: ContractState) -> u16 {
            let circle = self.current_circle.read();
            let section = self.current_section.read(circle);
            let section_len = lands_per_section(circle);

            let used_lands = self.get_used_index(circle, section);
            let random_index = get_random_available_index(circle, used_lands);
            self.used_lands_in_circle.entry((circle, section)).append().write(random_index);

            let index = section.into() * section_len + random_index;
            let land_location = get_circle_land_position(circle, index);

            self.handle_circle_completion_and_increment_section(circle, section);
            return land_location;
        }


        fn get_used_index(ref self: ContractState, circle: u16, section: u8) -> Array<u16> {
            let mut index = array![];
            let vec_len = self.used_lands_in_circle.entry((circle, section)).len();
            let mut i = 0;
            while i < vec_len {
                index.append(self.used_lands_in_circle.entry((circle, section)).at(i).read());
                i += 1;
            };
            index
        }

        fn handle_circle_completion_and_increment_section(
            ref self: ContractState, circle: u16, section: u8,
        ) {
            self.increment_section_count(circle, section);
            self.handle_circle_completion(circle);

            let circle = self.current_circle.read();
            let section = self.current_section.read(circle);
            let section_len = lands_per_section(circle);

            let used_lands = self.get_used_index(circle, section);
            if used_lands.len() == section_len.into() {
                self.advance_section(circle);
            }
        }

        fn increment_section_count(ref self: ContractState, circle: u16, section: u8) {
            let current_section_count = self.completed_lands_per_section.read((circle, section));
            self.completed_lands_per_section.write((circle, section), current_section_count + 1);
        }

        fn handle_circle_completion(ref self: ContractState, circle: u16) {
            let section = self.current_section.read(circle);
            let current_section_count = self.completed_lands_per_section.read((circle, section));
            let section_len = lands_per_section(circle);

            if section == 3 && current_section_count >= section_len {
                self.advance_circle(circle);
            }
        }

        fn advance_section(ref self: ContractState, circle: u16) {
            let section = self.current_section.read(circle);
            self.current_section.write(circle, section + 1);
        }

        fn advance_circle(ref self: ContractState, circle: u16) {
            self.current_circle.write(circle + 1);
            self.current_section.write(circle + 1, 0);
        }
    }
}
