use axum::{extract::State, http::StatusCode, Extension, Json};

use crate::{
    api::auth::ProjectContext,
    models::{error as app_error, request},
    DbPool,
};

pub async fn ingest_requests(
    State(pool): State<DbPool>,
    Extension(ctx): Extension<ProjectContext>,
    Json(batch): Json<request::RequestBatch>,
) -> StatusCode {
    // Non-blocking insert with backpressure handling
    match request::insert_batch(&pool, &batch, ctx.project_id) {
        Ok(count) => {
            tracing::debug!("Ingested {} requests (project_id={:?})", count, ctx.project_id);
            StatusCode::ACCEPTED
        }
        Err(e) => {
            // Log but don't fail - backpressure handling
            tracing::warn!("Failed to ingest requests: {}", e);
            StatusCode::ACCEPTED // Always return 202 to prevent retries
        }
    }
}

pub async fn ingest_errors(
    State(pool): State<DbPool>,
    Extension(ctx): Extension<ProjectContext>,
    Json(error): Json<app_error::IncomingError>,
) -> StatusCode {
    match app_error::insert(&pool, &error, ctx.project_id) {
        Ok(id) => {
            tracing::debug!("Ingested error id={} (project_id={:?})", id, ctx.project_id);
            StatusCode::ACCEPTED
        }
        Err(e) => {
            tracing::warn!("Failed to ingest error: {}", e);
            StatusCode::ACCEPTED // Always return 202 to prevent retries
        }
    }
}
