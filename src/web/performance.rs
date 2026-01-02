use askama::Template;
use axum::extract::{Query, State};
use chrono::{Duration, Utc};
use serde::Deserialize;
use tower_cookies::Cookies;

use crate::{models, DbPool};

use super::project_context::{get_project_context, WebProjectContext};

#[derive(Template)]
#[template(path = "performance/index.html")]
pub struct PerformanceTemplate {
    pub routes: Vec<models::request::RouteSummary>,
    pub period: String,
    pub ctx: WebProjectContext,
}

#[derive(Deserialize)]
pub struct PerformanceQuery {
    pub period: Option<String>,
}

pub async fn index(
    State(pool): State<DbPool>,
    cookies: Cookies,
    Query(query): Query<PerformanceQuery>,
) -> PerformanceTemplate {
    let ctx = get_project_context(&pool, &cookies);
    let project_id = ctx.project_id();
    let period = query.period.unwrap_or_else(|| "24h".to_string());

    let since = match period.as_str() {
        "7d" => Utc::now() - Duration::days(7),
        "30d" => Utc::now() - Duration::days(30),
        _ => Utc::now() - Duration::hours(24),
    };

    let routes = models::request::routes_summary(&pool, project_id, &since.to_rfc3339(), 50).unwrap_or_default();

    PerformanceTemplate { routes, period, ctx }
}
