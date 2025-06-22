use anyhow::{anyhow, Result};

use crate::config::{Conf, Token};

pub struct TokenService {
    pub tokens: Vec<Token>,
    pub main_token: Token,
}

impl TokenService {
    pub fn new(config: &Conf) -> Result<Self> {
        let main_token = config
            .token
            .iter()
            .find(|e| e.symbol == config.default_token)
            .ok_or_else(|| anyhow!("Impossible to find token!"))?;

        Ok(TokenService {
            tokens: config.token.clone(),
            main_token: main_token.clone(),
        })
    }

    #[must_use]
    pub fn list(&self) -> Vec<Token> {
        self.tokens.clone()
    }

    #[must_use]
    pub fn main_token(&self) -> &Token {
        &self.main_token
    }
}
