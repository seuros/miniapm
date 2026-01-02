use axum::{
    body::Body,
    extract::State,
    http::{header, Request, StatusCode},
    middleware::Next,
    response::Response,
};
use std::env;

use crate::DbPool;

/// Holds project information extracted from API key authentication
#[derive(Clone, Debug)]
pub struct ProjectContext {
    pub project_id: Option<i64>,
}

pub async fn auth_middleware(
    State(pool): State<DbPool>,
    mut request: Request<Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    // Extract Authorization header
    let auth_header = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok());

    let api_key = match auth_header {
        Some(h) if h.starts_with("Bearer ") => &h[7..],
        _ => return Err(StatusCode::UNAUTHORIZED),
    };

    // Check if projects are enabled and look up project by API key
    if env::var("ENABLE_PROJECTS").map(|v| v == "1" || v.to_lowercase() == "true").unwrap_or(false) {
        // Try to find project by API key
        match crate::models::project::find_by_api_key(&pool, api_key) {
            Ok(Some(project)) => {
                request.extensions_mut().insert(ProjectContext { project_id: Some(project.id) });
                return Ok(next.run(request).await);
            }
            Ok(None) => {
                // Fall through to check other auth methods
            }
            Err(_) => return Err(StatusCode::INTERNAL_SERVER_ERROR),
        }
    }

    // Check against env var (for simple setups without projects)
    if let Ok(env_key) = env::var("MINI_APM_API_KEY") {
        if api_key == env_key {
            request.extensions_mut().insert(ProjectContext { project_id: None });
            return Ok(next.run(request).await);
        }
    }

    // Then check database for legacy API keys
    match crate::models::api_key::verify(&pool, api_key) {
        Ok(true) => {
            request.extensions_mut().insert(ProjectContext { project_id: None });
            Ok(next.run(request).await)
        }
        Ok(false) => Err(StatusCode::UNAUTHORIZED),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}
