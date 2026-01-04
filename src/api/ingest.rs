use axum::{extract::State, http::StatusCode, Extension, Json};

use crate::{
    api::auth::ProjectContext,
    models::{deploy, span},
    DbPool,
};

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
