use ponzi_land::utils::level_up::calculate_discount_for_level;
use ponzi_land::helpers::coord::max_neighbors;
use ponzi_land::models::land::{Land, LandStake};
use ponzi_land::consts::{TAX_RATE, BASE_TIME, TIME_SPEED};
use starknet::{get_block_timestamp};

pub fn get_taxes_per_neighbor(land: Land, land_stake: LandStake) -> u256 {
    let current_time = get_block_timestamp();

    // Calculate the total taxes
    let elapsed_time = (current_time - land_stake.last_pay_time);

    let tax_rate_per_neighbor = get_tax_rate_per_neighbor(land);

    let tax_per_neighbor: u256 = (tax_rate_per_neighbor * elapsed_time.into()) / (BASE_TIME.into());

    tax_per_neighbor
}

pub fn get_tax_rate_per_neighbor(land: Land) -> u256 {
    let max_n = max_neighbors(land.location);
    if max_n == 0 {
        return 0;
    }

    let discount_for_level = calculate_discount_for_level(land.level);
    let base_tax_rate = (land.sell_price * TAX_RATE.into() * TIME_SPEED.into())
        / (max_n.into() * 100); // Base rate per neighbor

    let discounted_tax_rate = if discount_for_level > 0 {
        (base_tax_rate * (100 - discount_for_level).into()) / 100 // Apply 10% or 15% discount
    } else {
        base_tax_rate
    };

    discounted_tax_rate
}


pub fn get_time_to_nuke(land: Land, land_stake: LandStake, num_neighbors: u8) -> u256 {
    let tax_rate_per_neighbor = get_tax_rate_per_neighbor(land);
    let total_tax_rate = tax_rate_per_neighbor * num_neighbors.into();

    if total_tax_rate == 0 || TIME_SPEED == 0 {
        return 0;
    }

    let current_time: u256 = get_block_timestamp().into();
    // Calculate how many seconds it takes for taxes to equal stake amount
    // The tax accumulation per second is: (total_tax_rate * TIME_SPEED) / (100 * BASE_TIME)
    // So time to nuke = stake_amount / (tax per second)
    let seconds_to_nuke = (land_stake.amount * BASE_TIME.into()) / total_tax_rate;

    // The nuke time is the last payment time plus the seconds until nuke
    let nuke_time = land_stake.last_pay_time.into() + seconds_to_nuke;

    let mut res = 0;
    if nuke_time < current_time {
        res = 0;
    } else {
        res = nuke_time - current_time;
    }

    res
}
