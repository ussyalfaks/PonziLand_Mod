use serde::{Deserialize, Serialize};
use torii_ingester::{
    error::ToriiConversionError,
    get,
    prelude::{ContractAddress, Struct},
    u256::U256,
};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LandBoughtEvent {
    pub buyer: ContractAddress,
    pub land_location: Location,

    pub sold_price: U256,
    pub seller: ContractAddress,
    pub token_used: ContractAddress,
}

impl TryFrom<Struct> for LandBoughtEvent {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            buyer: get!(entity, "buyer", ContractAddress)?,
            land_location: get!(entity, "land_location", Location)?,

            sold_price: get!(entity, "sold_price", U256)?,
            seller: get!(entity, "seller", ContractAddress)?,
            token_used: get!(entity, "token_used", ContractAddress)?,
        })
    }
}
