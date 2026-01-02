use askama::Template;
use axum::extract::{Path, Query, State};
use serde::Deserialize;
use tower_cookies::Cookies;

use crate::{models, DbPool};

use super::project_context::{get_project_context, WebProjectContext};

#[derive(Template)]
#[template(path = "errors/index.html")]
pub struct ErrorsIndexTemplate {
    pub errors: Vec<models::AppError>,
    pub status_filter: Option<String>,
    pub ctx: WebProjectContext,
}

#[derive(Deserialize)]
pub struct ErrorsQuery {
    pub status: Option<String>,
}

pub async fn index(
    State(pool): State<DbPool>,
    cookies: Cookies,
    Query(query): Query<ErrorsQuery>,
) -> ErrorsIndexTemplate {
    let ctx = get_project_context(&pool, &cookies);
    let project_id = ctx.project_id();
    let errors = models::error::list(&pool, project_id, query.status.as_deref(), 100).unwrap_or_default();

    ErrorsIndexTemplate {
        errors,
        status_filter: query.status,
        ctx,
    }
}

#[derive(Template)]
#[template(path = "errors/show.html")]
pub struct ErrorShowTemplate {
    pub error: Option<models::AppError>,
    pub occurrences: Vec<models::ErrorOccurrence>,
    pub ctx: WebProjectContext,
}

pub async fn show(State(pool): State<DbPool>, cookies: Cookies, Path(id): Path<i64>) -> ErrorShowTemplate {
    let ctx = get_project_context(&pool, &cookies);
    let error = models::error::find(&pool, id).unwrap_or(None);
    let occurrences = if error.is_some() {
        models::error::occurrences(&pool, id, 10).unwrap_or_default()
    } else {
        vec![]
    };

    ErrorShowTemplate { error, occurrences, ctx }
}
