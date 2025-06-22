use serde::{Deserialize, Serialize};
use serde_aux::prelude::deserialize_number_from_string;
use torii_ingester::{
    error::ToriiConversionError,
    get,
    prelude::{ContractAddress, Struct},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddressRemovedEvent {
    pub address: ContractAddress,
    #[serde(deserialize_with = "deserialize_number_from_string")]
    pub authorized_at: u64,
}

impl TryFrom<Struct> for AddressRemovedEvent {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            address: get!(entity, "address", ContractAddress)?,
            authorized_at: get!(entity, "authorized_at", u64)?,
        })
    }
}
