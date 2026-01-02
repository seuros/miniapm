use crate::DbPool;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub id: Option<i64>,
    pub request_id: String,
    pub method: String,
    pub path: String,
    pub controller: Option<String>,
    pub action: Option<String>,
    pub status: i32,
    pub total_ms: f64,
    pub db_ms: f64,
    pub db_count: i32,
    pub view_ms: f64,
    pub host: Option<String>,
    pub env: Option<String>,
    pub git_sha: Option<String>,
    pub happened_at: String,
}

#[derive(Debug, Deserialize)]
pub struct RequestBatch {
    pub metadata: Option<RequestMetadata>,
    pub requests: Vec<IncomingRequest>,
}

#[derive(Debug, Deserialize)]
pub struct RequestMetadata {
    pub host: Option<String>,
    pub env: Option<String>,
    pub rails_version: Option<String>,
    pub ruby_version: Option<String>,
    pub git_sha: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct IncomingRequest {
    pub request_id: String,
    pub method: String,
    pub path: String,
    pub controller: Option<String>,
    pub action: Option<String>,
    pub status: i32,
    pub total_ms: f64,
    #[serde(default)]
    pub db_ms: f64,
    #[serde(default)]
    pub db_count: i32,
    #[serde(default)]
    pub view_ms: f64,
    pub timestamp: Option<String>,
}

pub fn insert_batch(
    pool: &DbPool,
    batch: &RequestBatch,
    project_id: Option<i64>,
) -> anyhow::Result<usize> {
    let conn = pool.get()?;
    let metadata = batch.metadata.as_ref();
    let now = chrono::Utc::now().to_rfc3339();

    let mut count = 0;
    for req in &batch.requests {
        conn.execute(
            r#"
            INSERT INTO requests
            (project_id, request_id, method, path, controller, action, status, total_ms, db_ms, db_count, view_ms, host, env, git_sha, happened_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
            "#,
            (
                project_id,
                &req.request_id,
                &req.method,
                &req.path,
                &req.controller,
                &req.action,
                req.status,
                req.total_ms,
                req.db_ms,
                req.db_count,
                req.view_ms,
                metadata.and_then(|m| m.host.as_ref()),
                metadata.and_then(|m| m.env.as_ref()),
                metadata.and_then(|m| m.git_sha.as_ref()),
                req.timestamp.as_ref().unwrap_or(&now),
            ),
        )?;
        count += 1;
    }

    Ok(count)
}

pub fn recent(pool: &DbPool, project_id: Option<i64>, limit: i64) -> anyhow::Result<Vec<Request>> {
    let conn = pool.get()?;
    let mut stmt = conn.prepare(
        r#"
        SELECT id, request_id, method, path, controller, action, status,
               total_ms, db_ms, db_count, view_ms, host, env, git_sha, happened_at
        FROM requests
        WHERE (?1 IS NULL OR project_id = ?1)
        ORDER BY happened_at DESC
        LIMIT ?2
        "#,
    )?;

    let requests = stmt
        .query_map(rusqlite::params![project_id, limit], |row| {
            Ok(Request {
                id: row.get(0)?,
                request_id: row.get(1)?,
                method: row.get(2)?,
                path: row.get(3)?,
                controller: row.get(4)?,
                action: row.get(5)?,
                status: row.get(6)?,
                total_ms: row.get(7)?,
                db_ms: row.get(8)?,
                db_count: row.get(9)?,
                view_ms: row.get(10)?,
                host: row.get(11)?,
                env: row.get(12)?,
                git_sha: row.get(13)?,
                happened_at: row.get(14)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(requests)
}

pub fn slow(pool: &DbPool, project_id: Option<i64>, threshold_ms: f64, limit: i64) -> anyhow::Result<Vec<Request>> {
    let conn = pool.get()?;
    let mut stmt = conn.prepare(
        r#"
        SELECT id, request_id, method, path, controller, action, status,
               total_ms, db_ms, db_count, view_ms, host, env, git_sha, happened_at
        FROM requests
        WHERE total_ms >= ?1 AND (?2 IS NULL OR project_id = ?2)
        ORDER BY total_ms DESC
        LIMIT ?3
        "#,
    )?;

    let requests = stmt
        .query_map(rusqlite::params![threshold_ms, project_id, limit], |row| {
            Ok(Request {
                id: row.get(0)?,
                request_id: row.get(1)?,
                method: row.get(2)?,
                path: row.get(3)?,
                controller: row.get(4)?,
                action: row.get(5)?,
                status: row.get(6)?,
                total_ms: row.get(7)?,
                db_ms: row.get(8)?,
                db_count: row.get(9)?,
                view_ms: row.get(10)?,
                host: row.get(11)?,
                env: row.get(12)?,
                git_sha: row.get(13)?,
                happened_at: row.get(14)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(requests)
}

pub fn count_since(pool: &DbPool, project_id: Option<i64>, since: &str) -> anyhow::Result<i64> {
    let conn = pool.get()?;
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM requests WHERE happened_at >= ?1 AND (?2 IS NULL OR project_id = ?2)",
        rusqlite::params![since, project_id],
        |row| row.get(0),
    )?;
    Ok(count)
}

pub fn avg_ms_since(pool: &DbPool, project_id: Option<i64>, since: &str) -> anyhow::Result<i64> {
    let conn = pool.get()?;
    let avg: f64 = conn
        .query_row(
            "SELECT COALESCE(AVG(total_ms), 0) FROM requests WHERE happened_at >= ?1 AND (?2 IS NULL OR project_id = ?2)",
            rusqlite::params![since, project_id],
            |row| row.get(0),
        )
        .unwrap_or(0.0);
    Ok(avg.round() as i64)
}

#[derive(Debug, Clone, Serialize)]
pub struct RouteSummary {
    pub path: String,
    pub method: String,
    pub request_count: i64,
    pub avg_ms: i64,
    pub p95_ms: Option<i64>,
    pub avg_db_ms: i64,
    pub avg_db_count: i64,
}

pub fn routes_summary(pool: &DbPool, project_id: Option<i64>, since: &str, limit: i64) -> anyhow::Result<Vec<RouteSummary>> {
    let conn = pool.get()?;
    let mut stmt = conn.prepare(
        r#"
        SELECT path, method,
               COUNT(*) as request_count,
               ROUND(AVG(total_ms)) as avg_ms,
               ROUND(AVG(db_ms)) as avg_db_ms,
               ROUND(AVG(db_count)) as avg_db_count
        FROM requests
        WHERE happened_at >= ?1 AND (?2 IS NULL OR project_id = ?2)
        GROUP BY path, method
        ORDER BY request_count DESC
        LIMIT ?3
        "#,
    )?;

    let routes = stmt
        .query_map(rusqlite::params![since, project_id, limit], |row| {
            Ok(RouteSummary {
                path: row.get(0)?,
                method: row.get(1)?,
                request_count: row.get(2)?,
                avg_ms: row.get::<_, f64>(3)? as i64,
                p95_ms: None,
                avg_db_ms: row.get::<_, f64>(4)? as i64,
                avg_db_count: row.get::<_, f64>(5)? as i64,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(routes)
}

pub fn delete_before(pool: &DbPool, project_id: Option<i64>, before: &str) -> anyhow::Result<usize> {
    let conn = pool.get()?;
    let deleted = conn.execute(
        "DELETE FROM requests WHERE happened_at < ?1 AND (?2 IS NULL OR project_id = ?2)",
        rusqlite::params![before, project_id],
    )?;
    Ok(deleted)
}

/// Display-friendly request with rounded ms values and formatted timestamp
#[derive(Debug, Clone)]
pub struct RequestDisplay {
    pub method: String,
    pub path: String,
    pub status: i32,
    pub total_ms: i64,
    pub db_ms: i64,
    pub view_ms: i64,
    pub happened_at: String,
}

pub fn slow_display(pool: &DbPool, project_id: Option<i64>, threshold_ms: f64, limit: i64) -> anyhow::Result<Vec<RequestDisplay>> {
    let conn = pool.get()?;
    let mut stmt = conn.prepare(
        r#"
        SELECT method, path, status,
               ROUND(total_ms) as total_ms,
               ROUND(db_ms) as db_ms,
               ROUND(view_ms) as view_ms,
               strftime('%Y-%m-%d %H:%M', happened_at) as happened_at
        FROM requests
        WHERE total_ms >= ?1 AND (?2 IS NULL OR project_id = ?2)
        ORDER BY total_ms DESC
        LIMIT ?3
        "#,
    )?;

    let requests = stmt
        .query_map(rusqlite::params![threshold_ms, project_id, limit], |row| {
            Ok(RequestDisplay {
                method: row.get(0)?,
                path: row.get(1)?,
                status: row.get(2)?,
                total_ms: row.get::<_, f64>(3)? as i64,
                db_ms: row.get::<_, f64>(4)? as i64,
                view_ms: row.get::<_, f64>(5)? as i64,
                happened_at: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(requests)
}
