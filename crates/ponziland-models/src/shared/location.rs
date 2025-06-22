use std::{
    fmt::{self, Debug},
    num::ParseIntError,
    str::FromStr,
};

use serde::{
    de,
    de::{MapAccess, SeqAccess, Visitor},
    ser::SerializeMap,
    Deserialize, Deserializer, Serialize,
};
use torii_ingester::{
    conversions::{FromPrimitive, Primitive},
    error::ToriiConversionError,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(transparent)]
pub struct Location(pub u64);

impl Location {
    fn coordinates(self) -> (u64, u64) {
        (self.0 / 64, self.0 % 64)
    }
}
impl std::fmt::Display for Location {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let (x, y) = self.coordinates();
        write!(f, "({x}, {y})")
    }
}

impl From<(u64, u64)> for Location {
    fn from((x, y): (u64, u64)) -> Self {
        Location(x * 64 + y)
    }
}

impl FromPrimitive for Location {
    fn from_primitive(primitive: Primitive) -> Result<Self, ToriiConversionError> {
        match primitive.as_u16() {
            Some(e) => Ok(Location(u64::from(e))),
            None => Err(ToriiConversionError::WrongType {
                expected: "Location (u16)".to_string(),
                got: format!("{primitive:?}"),
            }),
        }
    }
}

impl Serialize for Location {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        // Write a new object, and then two numbers within
        let mut object = serializer.serialize_map(Some(2))?;
        let (x, y) = self.coordinates();

        object.serialize_entry(&"x", &x)?;
        object.serialize_entry(&"y", &y)?;

        object.end()
    }
}

impl<'de> Deserialize<'de> for Location {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(field_identifier, rename_all = "lowercase")]
        enum Field {
            X,
            Y,
        }

        struct LocationVisitor;

        impl<'de> Visitor<'de> for LocationVisitor {
            type Value = Location;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("string, number or map")
            }

            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                FromStr::from_str(value)
                    .map_err(|_| serde::de::Error::custom("String value is not a number!"))
            }

            fn visit_u64<E>(self, v: u64) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(Location::from(v))
            }

            fn visit_seq<V>(self, mut seq: V) -> Result<Self::Value, V::Error>
            where
                V: SeqAccess<'de>,
            {
                let x = seq
                    .next_element()?
                    .ok_or_else(|| de::Error::invalid_length(0, &self))?;
                let y = seq
                    .next_element()?
                    .ok_or_else(|| de::Error::invalid_length(1, &self))?;
                Ok(Location::from((x, y)))
            }

            fn visit_map<M>(self, mut map: M) -> Result<Self::Value, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut x = None;
                let mut y = None;

                while let Some(key) = map.next_key()? {
                    match key {
                        Field::X => {
                            if x.is_some() {
                                return Err(de::Error::duplicate_field("x"));
                            }
                            x = Some(map.next_value()?);
                        }
                        Field::Y => {
                            if y.is_some() {
                                return Err(de::Error::duplicate_field("y"));
                            }
                            y = Some(map.next_value()?);
                        }
                    }
                }
                let x = x.ok_or_else(|| de::Error::missing_field("x"))?;
                let y = y.ok_or_else(|| de::Error::missing_field("y"))?;
                Ok(Location::from((x, y)))
            }
        }

        deserializer.deserialize_any(LocationVisitor)
    }
}

impl FromStr for Location {
    type Err = ParseIntError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let number = if let Some(stripped) = s.strip_prefix("0x") {
            u64::from_str_radix(stripped, 16)?
        } else {
            u64::from_str(s)?
        };
        Ok(Location(number))
    }
}

impl From<u64> for Location {
    fn from(value: u64) -> Self {
        Location(value)
    }
}

impl From<Location> for i16 {
    // We know that 64*64 cannot overflow an i16
    #[allow(clippy::cast_possible_truncation)]
    fn from(location: Location) -> Self {
        location.0 as i16
    }
}

#[cfg(test)]
mod test {
    use super::Location;

    #[test]
    fn test_deserialization_number() {
        let json = "1";
        let deserialized: Location =
            serde_json::from_str(json).expect("Error while deserialing from int");
        assert_eq!(deserialized, Location(1));
    }

    #[test]
    fn test_deserialization_string() {
        let json = r#""2""#;
        let deserialized: Location =
            serde_json::from_str(json).expect("Error while deserialing from hex int");
        assert_eq!(deserialized, Location(2));

        let json = r#""0xa""#;
        let deserialized: Location =
            serde_json::from_str(json).expect("Error while deserialing from hex int");
        assert_eq!(deserialized, Location(10));

        let json = r#""abc""#;
        let result = serde_json::from_str::<Location>(json);
        assert!(result.is_err());
    }
}
