use std::ops::Deref;

use ponziland_models::shared::Location as RawLocation;
use serde::{Deserialize, Serialize};
use sqlx::{prelude::Type, Decode, Encode, Postgres};
use torii_ingester::{
    conversions::{FromPrimitive, Primitive},
    error::ToriiConversionError,
};

// Database-aware wrapper for the on-chain Location.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(transparent)]
#[serde(transparent)]
pub struct Location(RawLocation);

impl Type<Postgres> for Location {
    fn type_info() -> <Postgres as sqlx::Database>::TypeInfo {
        <i32 as Type<Postgres>>::type_info()
    }
}

impl FromPrimitive for Location {
    fn from_primitive(value: Primitive) -> Result<Location, ToriiConversionError> {
        RawLocation::from_primitive(value).map(Location)
    }
}

impl Location {
    #[must_use]
    pub fn new(value: u64) -> Self {
        Location(RawLocation(value))
    }

    #[must_use]
    pub fn coords(x: u64, y: u64) -> Self {
        Location(RawLocation::from((x, y)))
    }
}

impl From<u64> for Location {
    fn from(value: u64) -> Self {
        Location::new(value)
    }
}

impl<'a> Decode<'a, Postgres> for Location {
    fn decode(
        value: <Postgres as sqlx::Database>::ValueRef<'a>,
    ) -> Result<Self, sqlx::error::BoxDynError> {
        // We're never allowing negative locations
        #[allow(clippy::cast_sign_loss)]
        <i32 as Decode<'a, Postgres>>::decode(value).map(|val| Location(RawLocation(val as u64)))
    }
}

impl<'a> Encode<'a, Postgres> for Location {
    fn encode_by_ref(
        &self,
        buf: &mut <Postgres as sqlx::Database>::ArgumentBuffer<'a>,
    ) -> Result<sqlx::encode::IsNull, sqlx::error::BoxDynError> {
        // We have the guarantee that the value fits into an i32
        #[allow(clippy::cast_possible_truncation)]
        <i32 as Encode<'a, Postgres>>::encode_by_ref(&(self.0 .0 as i32), buf)
    }
}

impl From<RawLocation> for Location {
    fn from(value: RawLocation) -> Self {
        Location(value)
    }
}

impl AsRef<RawLocation> for Location {
    fn as_ref(&self) -> &RawLocation {
        &self.0
    }
}

impl Deref for Location {
    type Target = RawLocation;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
