use std::future::ready;

use ::axum::{routing::get, serve, serve::Serve, Router};
use anyhow::{Context, Result};
use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};
use tracing::info;

use crate::config::Conf;

pub mod apalis;
pub mod axum;

/// Listen for monitoring requests.
///
/// # Errors
///
/// This function will return an error if the TCP listener fails to bind to the specified address.
///
pub async fn listen_monitoring(
    config: &Conf,
) -> Result<Serve<tokio::net::TcpListener, Router, Router>> {
    let recorder = recorder()?;

    // run our app with hyper, listening globally on the chosen address and port
    let address = format!("{}:{}", config.monitoring.address, config.monitoring.port);

    let listener = tokio::net::TcpListener::bind(&address)
        .await
        .with_context(|| format!("Attempt to listed on {address} failed!"))?;

    info!(
        "Monitoring service listening on http://{}{}",
        listener.local_addr()?,
        config.monitoring.path
    );

    let app = Router::new()
        // `GET /` goes to `root`
        .route(
            &config.monitoring.path,
            get(move || ready(recorder.render())),
        );

    Ok(serve(listener, app))
}

/// Create a Prometheus recorder.
///
/// # Errors
///
/// This function will return an error if the Prometheus recorder fails to install.
pub fn recorder() -> Result<PrometheusHandle> {
    PrometheusBuilder::new()
        .install_recorder()
        .with_context(|| "Could not install Prometheus recorder")
}
