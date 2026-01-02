use axum::{extract::State, Json};
use serde::Serialize;
use std::time::Instant;

use crate::{db, DbPool};

static START_TIME: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

pub fn init_start_time() {
    START_TIME.get_or_init(Instant::now);
}

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub db_size_mb: f64,
    pub uptime_seconds: u64,
}

pub async fn health_handler(State(pool): State<DbPool>) -> Json<HealthResponse> {
    let db_size_mb = db::get_db_size(&pool).unwrap_or(0.0);
    let uptime_seconds = START_TIME
        .get()
        .map(|t| t.elapsed().as_secs())
        .unwrap_or(0);

    Json(HealthResponse {
        status: "ok".to_string(),
        db_size_mb,
        uptime_seconds,
    })
}
