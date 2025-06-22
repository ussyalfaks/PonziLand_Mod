#[macro_export]
macro_rules! define_id {
    ($name: ident, Uuid) => {
        #[derive(
            Clone,
            Copy,
            PartialEq,
            Eq,
            Debug,
            sqlx::Type,
            Hash,
            serde::Serialize,
            serde::Deserialize,
        )]
        #[sqlx(transparent, type_name = "uuid")]
        pub struct $name(pub uuid::Uuid);

        impl From<uuid::Uuid> for $name {
            fn from(uuid: uuid::Uuid) -> Self {
                $name(uuid)
            }
        }

        impl From<$name> for uuid::Uuid {
            fn from(id: $name) -> Self {
                id.0
            }
        }
        impl AsRef<uuid::Uuid> for $name {
            fn as_ref(&self) -> &uuid::Uuid {
                &self.0
            }
        }

        impl Default for $name {
            fn default() -> Self {
                Self::new()
            }
        }

        impl $name {
            #[must_use]
            pub fn new() -> Self {
                $name(uuid::Uuid::new_v4())
            }
        }
    };
}
