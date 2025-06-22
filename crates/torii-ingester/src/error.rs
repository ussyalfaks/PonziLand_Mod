#[derive(thiserror::Error, Debug)]
pub enum ToriiConversionError {
    #[error("No such field: {0}")]
    NoSuchField(String),

    #[error("Wrong type: expected {expected}, got {got}")]
    WrongType { expected: String, got: String },

    #[error("Unknown variant for enum {enum_name}: {variant_name}")]
    UnknownVariant {
        enum_name: String,
        variant_name: String,
    },

    #[error("JSON deserialization error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("error while processing {0}: {1}")]
    NestedError(String, Box<ToriiConversionError>),
}
