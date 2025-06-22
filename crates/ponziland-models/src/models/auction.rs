use serde::{Deserialize, Serialize};
use serde_aux::prelude::deserialize_number_from_string;
use torii_ingester::{error::ToriiConversionError, get, prelude::Struct, u256::U256};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Model {
    pub land_location: Location,
    #[serde(deserialize_with = "deserialize_number_from_string")]
    pub start_time: u64,
    pub start_price: U256,
    pub floor_price: U256,
    pub is_finished: bool,
    pub decay_rate: u16,
    pub sold_at_price: Option<U256>,
}

impl TryFrom<Struct> for Model {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            land_location: get!(entity, "land_location", Location)?,
            start_time: get!(entity, "start_time", u64)?,
            start_price: get!(entity, "start_price", U256)?,
            floor_price: get!(entity, "floor_price", U256)?,
            is_finished: get!(entity, "is_finished", bool)?,
            decay_rate: get!(entity, "decay_rate", u16)?,
            sold_at_price: get!(entity, "sold_at_price", Option<U256>)?,
        })
    }
}
