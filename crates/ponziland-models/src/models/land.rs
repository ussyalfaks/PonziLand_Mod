use serde::{Deserialize, Serialize};
use serde_aux::prelude::deserialize_number_from_string;
use torii_ingester::{
    conversions::torii_enum_deserializer,
    conversions::FromTy,
    error::ToriiConversionError,
    get,
    prelude::{ContractAddress, Struct, Ty},
    u256::U256,
};

use crate::shared::Location;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Copy)]
#[repr(i32)]
pub enum Level {
    Zero = 0,
    First = 1,
    Second = 2,
}

impl FromTy for Level {
    // TODO(Red): When we bump the minimum rustc version, we can use if let, that could reduce nesting.
    fn from_ty(value: Ty) -> Result<Self, ToriiConversionError> {
        match value {
            Ty::Enum(enum_data) => {
                if let Ok(variant) = enum_data.option() {
                    match &*variant.name {
                        "Zero" => Ok(Level::Zero),
                        "First" => Ok(Level::First),
                        "Second" => Ok(Level::Second),
                        name => Err(ToriiConversionError::UnknownVariant {
                            enum_name: "Option".to_string(),
                            variant_name: name.to_string(),
                        }),
                    }
                } else {
                    Err(ToriiConversionError::WrongType {
                        expected: "enum".to_string(),
                        got: enum_data.name,
                    })
                }
            }
            _ => Err(ToriiConversionError::WrongType {
                expected: "enum".to_string(),
                got: value.name(),
            }),
        }
    }
}

/// Rust representation of the on-chain land model.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Land {
    pub location: Location,
    #[serde(deserialize_with = "deserialize_number_from_string")]
    pub block_date_bought: u64,
    pub owner: ContractAddress,
    pub sell_price: U256,
    pub token_used: ContractAddress,
    #[serde(deserialize_with = "torii_enum_deserializer")]
    pub level: Level,
}

impl TryFrom<Struct> for Land {
    type Error = ToriiConversionError;

    fn try_from(entity: Struct) -> Result<Self, Self::Error> {
        Ok(Self {
            location: get!(entity, "location", Location)?,
            block_date_bought: get!(entity, "block_date_bought", u64)?,
            owner: get!(entity, "owner", ContractAddress)?,
            sell_price: get!(entity, "sell_price", U256)?,
            token_used: get!(entity, "token_used", ContractAddress)?,
            level: get!(entity, "level", Level)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_land_model_deserialization_torii() {
        let json = r#"
            {
              "block_date_bought":"0",
              "level":{"Zero":[]},
              "location":2080,
              "owner":"0x0",
              "sell_price":"0x000000000000000000000000000000000000000000000006f05b59d3b2000000",
              "token_used":"0x5735fa6be5dd248350866644c0a137e571f9d637bb4db6532ddd63a95854b58"
            }
            "#;

        let deserialization =
            serde_json::from_str::<Land>(json).expect("Error while deserializing!");

        assert_eq!(deserialization.level, Level::Zero);
    }
}
