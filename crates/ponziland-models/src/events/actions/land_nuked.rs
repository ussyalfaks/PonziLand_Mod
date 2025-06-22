use serde::{Deserialize, Serialize};
use torii_ingester::{
    error::ToriiConversionError,
    get,
    prelude::{ContractAddress, Struct},
};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LandNukedEvent {
    pub owner_nuked: ContractAddress,
    pub land_location: Location,
}

impl TryFrom<Struct> for LandNukedEvent {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            owner_nuked: get!(entity, "owner_nuked", ContractAddress)?,
            land_location: get!(entity, "land_location", Location)?,
        })
    }
}
