use serde::{Deserialize, Serialize};
use serde_aux::prelude::deserialize_number_from_string;
use torii_ingester::{error::ToriiConversionError, get, prelude::Struct, u256::U256};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LandStake {
    pub location: Location,
    #[serde(deserialize_with = "deserialize_number_from_string")]
    pub last_pay_time: u64,
    pub amount: U256,
}

impl TryFrom<Struct> for LandStake {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            location: get!(entity, "location", Location)?,
            last_pay_time: get!(entity, "last_pay_time", u64)?,
            amount: get!(entity, "amount", U256)?,
        })
    }
}
