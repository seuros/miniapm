use askama::Template;
use axum::extract::State;
use tower_cookies::Cookies;

use crate::{models, DbPool};

use super::project_context::{get_project_context, WebProjectContext};

#[derive(Template)]
#[template(path = "slow_requests.html")]
pub struct SlowRequestsTemplate {
    pub requests: Vec<models::request::RequestDisplay>,
    pub threshold_ms: i64,
    pub ctx: WebProjectContext,
}

pub async fn index(State(pool): State<DbPool>, cookies: Cookies) -> SlowRequestsTemplate {
    let ctx = get_project_context(&pool, &cookies);
    let project_id = ctx.project_id();
    let threshold_ms = 500.0;
    let requests = models::request::slow_display(&pool, project_id, threshold_ms, 100).unwrap_or_default();

    SlowRequestsTemplate {
        requests,
        threshold_ms: threshold_ms as i64,
        ctx,
    }
}
