use askama::Template;
use axum::extract::State;
use chrono::{Duration, Utc};
use tower_cookies::Cookies;

use crate::{models, DbPool};

use super::project_context::{get_project_context, WebProjectContext};

#[derive(Template)]
#[template(path = "dashboard.html")]
pub struct DashboardTemplate {
    pub requests_24h: i64,
    pub errors_24h: i64,
    pub avg_ms: i64,
    pub recent_errors: Vec<models::AppError>,
    pub slow_routes: Vec<models::request::RouteSummary>,
    pub ctx: WebProjectContext,
}

pub async fn index(State(pool): State<DbPool>, cookies: Cookies) -> DashboardTemplate {
    let ctx = get_project_context(&pool, &cookies);
    let project_id = ctx.project_id();
    let since = (Utc::now() - Duration::hours(24)).to_rfc3339();

    let requests_24h = models::request::count_since(&pool, project_id, &since).unwrap_or(0);
    let errors_24h = models::error::count_since(&pool, project_id, &since).unwrap_or(0);
    let avg_ms = models::request::avg_ms_since(&pool, project_id, &since).unwrap_or(0);
    let recent_errors = models::error::list(&pool, project_id, Some("open"), 5).unwrap_or_default();
    let slow_routes = models::request::routes_summary(&pool, project_id, &since, 5).unwrap_or_default();

    DashboardTemplate {
        requests_24h,
        errors_24h,
        avg_ms,
        recent_errors,
        slow_routes,
        ctx,
    }
}
