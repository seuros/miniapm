use axum::{extract::State, http::StatusCode, Extension, Json};

use crate::{
    api::auth::ProjectContext,
    models::{deploy, error as app_error, request, span},
    DbPool,
};

pub async fn ingest_requests(
    State(pool): State<DbPool>,
    Extension(ctx): Extension<ProjectContext>,
    Json(batch): Json<request::RequestBatch>,
) -> StatusCode {
    match request::insert_batch(&pool, &batch, ctx.project_id) {
        Ok(count) => {
            tracing::debug!("Ingested {} requests (project_id={:?})", count, ctx.project_id);
            StatusCode::ACCEPTED
        }
        Err(e) => {
            tracing::error!("Failed to ingest requests: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
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
            tracing::error!("Failed to ingest error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

pub async fn ingest_spans(
    State(pool): State<DbPool>,
    Extension(ctx): Extension<ProjectContext>,
    Json(otlp_request): Json<span::OtlpTraceRequest>,
) -> StatusCode {
    match span::insert_otlp_batch(&pool, &otlp_request, ctx.project_id) {
        Ok(count) => {
            tracing::debug!("Ingested {} spans (project_id={:?})", count, ctx.project_id);
            StatusCode::ACCEPTED
        }
        Err(e) => {
            tracing::error!("Failed to ingest spans: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

pub async fn ingest_deploys(
    State(pool): State<DbPool>,
    Extension(ctx): Extension<ProjectContext>,
    Json(incoming): Json<deploy::IncomingDeploy>,
) -> StatusCode {
    match deploy::insert(&pool, &incoming, ctx.project_id) {
        Ok(id) => {
            tracing::info!(
                "Recorded deploy id={} git_sha={} (project_id={:?})",
                id,
                incoming.git_sha,
                ctx.project_id
            );
            StatusCode::ACCEPTED
        }
        Err(e) => {
            tracing::error!("Failed to record deploy: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}
