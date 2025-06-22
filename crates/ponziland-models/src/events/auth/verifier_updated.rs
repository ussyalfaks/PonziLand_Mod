use serde::{Deserialize, Serialize};
use starknet::core::types::Felt;
use torii_ingester::{error::ToriiConversionError, get, prelude::Struct};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifierUpdatedEvent {
    pub new_verifier: Felt,
    pub old_verifier: Felt,
}

impl TryFrom<Struct> for VerifierUpdatedEvent {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            new_verifier: get!(entity, "new_verifier", Felt)?,
            old_verifier: get!(entity, "old_verifier", Felt)?,
        })
    }
}
