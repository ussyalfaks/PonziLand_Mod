use reqwest::Url;
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostRequest {
    #[serde(rename = "playerAddress")]
    pub address: String,
    pub actions: Vec<String>,
}

pub struct GGApi {
    client: reqwest::Client,
    path: Url,
    token: String,
}

impl GGApi {
    /// Creates a new GG.xyz API client
    ///
    /// # Panics
    /// Panics if the URL is invalid
    #[must_use]
    pub fn new(base_url: &Url, token: String) -> Self {
        let path = base_url
            .join("/api/v2/action-dispatcher/dispatch/public")
            .expect("Could not setup URL correctly.");

        Self {
            client: reqwest::Client::new(),
            path,
            token,
        }
    }

    /// Sends an action to the GG.xyz API
    ///
    /// # Errors
    /// Returns an error if the request fails or the response from the remote server is not a 200
    pub async fn send_actions(&self, req: PostRequest) -> Result<(), reqwest::Error> {
        // Set the path, but keep the rest from the base path.
        let response = self
            .client
            .post(self.path.clone())
            .header("secret", &self.token)
            .json(&req)
            .send()
            .await?;

        if let Err(err) = response.error_for_status_ref() {
            info!("Body: {}", response.text().await?);
            Err(err)
        } else {
            Ok(())
        }
    }
}
