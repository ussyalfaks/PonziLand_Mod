use chrono::{DateTime, NaiveDateTime};

/// Converts a Unix timestamp to a `NaiveDateTime`.
///
/// # Panics
/// If the unix timestamp is negative
#[must_use]
pub fn naive_from_u64(unix_timestamp: u64) -> NaiveDateTime {
    DateTime::from_timestamp(i64::try_from(unix_timestamp).unwrap(), 0)
        .unwrap()
        .naive_utc()
}
