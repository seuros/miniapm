mod retention;
mod rollup;

use crate::{config::Config, DbPool};
use std::time::Duration;
use tokio::time::interval;

pub fn start(pool: DbPool, config: Config) {
    // Hourly rollup job
    let pool_clone = pool.clone();
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_secs(3600)); // Every hour
        loop {
            interval.tick().await;
            if let Err(e) = rollup::hourly(&pool_clone) {
                tracing::error!("Hourly rollup failed: {}", e);
            }
        }
    });

    // Daily rollup job
    let pool_clone = pool.clone();
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_secs(86400)); // Every 24 hours
        loop {
            interval.tick().await;
            if let Err(e) = rollup::daily(&pool_clone) {
                tracing::error!("Daily rollup failed: {}", e);
            }
        }
    });

    // Retention job
    let pool_clone = pool.clone();
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_secs(86400)); // Every 24 hours
        loop {
            interval.tick().await;
            if let Err(e) = retention::cleanup(&pool_clone, &config) {
                tracing::error!("Retention cleanup failed: {}", e);
            }
        }
    });

    tracing::info!("Background jobs started");
}
