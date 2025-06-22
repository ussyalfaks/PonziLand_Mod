use torii_ingester::torii_client;

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("Error while connecting to the database")]
    ToriiConnectionError(#[from] torii_client::Error),
}
