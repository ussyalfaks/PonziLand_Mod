use serde::{Deserialize, Serialize};
use torii_ingester::{error::ToriiConversionError, get, prelude::Struct, u256::U256};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewAuctionEvent {
    pub land_location: Location,
    pub start_price: U256,
    pub floor_price: U256,
}

impl TryFrom<Struct> for NewAuctionEvent {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            land_location: get!(entity, "land_location", Location)?,
            start_price: get!(entity, "start_price", U256)?,
            floor_price: get!(entity, "floor_price", U256)?,
        })
    }
}
