use serde::{Deserialize, Serialize};
use torii_ingester::{
    error::ToriiConversionError,
    get,
    prelude::{ContractAddress, Struct},
    u256::U256,
};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuctionFinishedEvent {
    pub land_location: Location,
    pub buyer: ContractAddress,
    pub final_price: U256,
}

impl TryFrom<Struct> for AuctionFinishedEvent {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            land_location: get!(entity, "land_location", Location)?,
            buyer: get!(entity, "buyer", ContractAddress)?,
            final_price: get!(entity, "final_price", U256)?,
        })
    }
}
