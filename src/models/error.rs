use crate::DbPool;
use chrono::Utc;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppError {
    pub id: i64,
    pub fingerprint: String,
    pub exception_class: String,
    pub message: String,
    pub first_seen_at: String,
    pub last_seen_at: String,
    pub occurrence_count: i64,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorOccurrence {
    pub id: i64,
    pub error_id: i64,
    pub request_id: Option<String>,
    pub user_id: Option<String>,
    pub backtrace: Vec<String>,
    pub params: Option<serde_json::Value>,
    pub happened_at: String,
}

#[derive(Debug, Deserialize)]
pub struct IncomingError {
    pub exception_class: String,
    pub message: String,
    pub backtrace: Vec<String>,
    pub fingerprint: String,
    pub request_id: Option<String>,
    pub user_id: Option<String>,
    pub params: Option<serde_json::Value>,
    pub timestamp: Option<String>,
}

pub fn insert(pool: &DbPool, error: &IncomingError, project_id: Option<i64>) -> anyhow::Result<i64> {
    let conn = pool.get()?;
    let now = Utc::now().to_rfc3339();
    let timestamp = error.timestamp.as_ref().unwrap_or(&now);

    // Try to find existing error by fingerprint and project_id
    let existing: Option<i64> = conn
        .query_row(
            "SELECT id FROM errors WHERE fingerprint = ?1 AND ((?2 IS NULL AND project_id IS NULL) OR project_id = ?2)",
            rusqlite::params![&error.fingerprint, project_id],
            |row| row.get(0),
        )
        .ok();

    let error_id = if let Some(id) = existing {
        // Update existing error
        conn.execute(
            "UPDATE errors SET last_seen_at = ?1, occurrence_count = occurrence_count + 1 WHERE id = ?2",
            (timestamp, id),
        )?;
        id
    } else {
        // Insert new error
        conn.execute(
            r#"
            INSERT INTO errors (project_id, fingerprint, exception_class, message, first_seen_at, last_seen_at, occurrence_count, status)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1, 'open')
            "#,
            (
                project_id,
                &error.fingerprint,
                &error.exception_class,
                &error.message,
                timestamp,
                timestamp,
            ),
        )?;
        conn.last_insert_rowid()
    };

    // Insert occurrence
    conn.execute(
        r#"
        INSERT INTO error_occurrences (error_id, request_id, user_id, backtrace, params, happened_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
        (
            error_id,
            &error.request_id,
            &error.user_id,
            serde_json::to_string(&error.backtrace)?,
            error.params.as_ref().map(|p| serde_json::to_string(p).ok()).flatten(),
            timestamp,
        ),
    )?;

    Ok(error_id)
}

pub fn list(pool: &DbPool, project_id: Option<i64>, status: Option<&str>, limit: i64) -> anyhow::Result<Vec<AppError>> {
    let conn = pool.get()?;

    let sql = match (status.is_some(), project_id.is_some()) {
        (true, true) => {
            "SELECT id, fingerprint, exception_class, message,
                    strftime('%Y-%m-%d %H:%M', first_seen_at),
                    strftime('%Y-%m-%d %H:%M', last_seen_at),
                    occurrence_count, status
             FROM errors WHERE status = ?1 AND project_id = ?2 ORDER BY last_seen_at DESC LIMIT ?3"
        }
        (true, false) => {
            "SELECT id, fingerprint, exception_class, message,
                    strftime('%Y-%m-%d %H:%M', first_seen_at),
                    strftime('%Y-%m-%d %H:%M', last_seen_at),
                    occurrence_count, status
             FROM errors WHERE status = ?1 ORDER BY last_seen_at DESC LIMIT ?2"
        }
        (false, true) => {
            "SELECT id, fingerprint, exception_class, message,
                    strftime('%Y-%m-%d %H:%M', first_seen_at),
                    strftime('%Y-%m-%d %H:%M', last_seen_at),
                    occurrence_count, status
             FROM errors WHERE project_id = ?1 ORDER BY last_seen_at DESC LIMIT ?2"
        }
        (false, false) => {
            "SELECT id, fingerprint, exception_class, message,
                    strftime('%Y-%m-%d %H:%M', first_seen_at),
                    strftime('%Y-%m-%d %H:%M', last_seen_at),
                    occurrence_count, status
             FROM errors ORDER BY last_seen_at DESC LIMIT ?1"
        }
    };

    let mut stmt = conn.prepare(sql)?;
    let errors = match (status, project_id) {
        (Some(s), Some(p)) => stmt.query_map(rusqlite::params![s, p, limit], map_error)?,
        (Some(s), None) => stmt.query_map(rusqlite::params![s, limit], map_error)?,
        (None, Some(p)) => stmt.query_map(rusqlite::params![p, limit], map_error)?,
        (None, None) => stmt.query_map(rusqlite::params![limit], map_error)?,
    };

    errors.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

pub fn find(pool: &DbPool, id: i64) -> anyhow::Result<Option<AppError>> {
    let conn = pool.get()?;
    let error = conn
        .query_row(
            "SELECT id, fingerprint, exception_class, message,
                    strftime('%Y-%m-%d %H:%M', first_seen_at),
                    strftime('%Y-%m-%d %H:%M', last_seen_at),
                    occurrence_count, status
             FROM errors WHERE id = ?1",
            [id],
            map_error,
        )
        .ok();
    Ok(error)
}

pub fn occurrences(pool: &DbPool, error_id: i64, limit: i64) -> anyhow::Result<Vec<ErrorOccurrence>> {
    let conn = pool.get()?;
    let mut stmt = conn.prepare(
        "SELECT id, error_id, request_id, user_id, backtrace, params,
                strftime('%Y-%m-%d %H:%M', happened_at)
         FROM error_occurrences WHERE error_id = ?1 ORDER BY happened_at DESC LIMIT ?2",
    )?;

    let occs = stmt
        .query_map([error_id, limit], |row| {
            let backtrace_str: String = row.get(4)?;
            let params_str: Option<String> = row.get(5)?;
            Ok(ErrorOccurrence {
                id: row.get(0)?,
                error_id: row.get(1)?,
                request_id: row.get(2)?,
                user_id: row.get(3)?,
                backtrace: serde_json::from_str(&backtrace_str).unwrap_or_default(),
                params: params_str.and_then(|s| serde_json::from_str(&s).ok()),
                happened_at: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(occs)
}

pub fn count_since(pool: &DbPool, project_id: Option<i64>, since: &str) -> anyhow::Result<i64> {
    let conn = pool.get()?;
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM error_occurrences eo
         JOIN errors e ON e.id = eo.error_id
         WHERE eo.happened_at >= ?1 AND (?2 IS NULL OR e.project_id = ?2)",
        rusqlite::params![since, project_id],
        |row| row.get(0),
    )?;
    Ok(count)
}

pub fn update_status(pool: &DbPool, id: i64, status: &str) -> anyhow::Result<()> {
    let conn = pool.get()?;
    conn.execute("UPDATE errors SET status = ?1 WHERE id = ?2", (status, id))?;
    Ok(())
}

pub fn delete_occurrences_before(pool: &DbPool, before: &str) -> anyhow::Result<usize> {
    let conn = pool.get()?;
    let deleted = conn.execute("DELETE FROM error_occurrences WHERE happened_at < ?1", [before])?;
    Ok(deleted)
}

fn map_error(row: &rusqlite::Row) -> rusqlite::Result<AppError> {
    Ok(AppError {
        id: row.get(0)?,
        fingerprint: row.get(1)?,
        exception_class: row.get(2)?,
        message: row.get(3)?,
        first_seen_at: row.get(4)?,
        last_seen_at: row.get(5)?,
        occurrence_count: row.get(6)?,
        status: row.get(7)?,
    })
}
