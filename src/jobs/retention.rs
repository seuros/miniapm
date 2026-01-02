use crate::{config::Config, models, DbPool};
use chrono::{Duration, Utc};

pub fn cleanup(pool: &DbPool, config: &Config) -> anyhow::Result<()> {
    // Delete old requests (across all projects)
    let requests_cutoff = (Utc::now() - Duration::days(config.retention_days_requests))
        .to_rfc3339();
    let deleted_requests = models::request::delete_before(pool, None, &requests_cutoff)?;
    tracing::info!("Deleted {} old requests", deleted_requests);

    // Delete old error occurrences
    let errors_cutoff = (Utc::now() - Duration::days(config.retention_days_errors))
        .to_rfc3339();
    let deleted_occurrences = models::error::delete_occurrences_before(pool, &errors_cutoff)?;
    tracing::info!("Deleted {} old error occurrences", deleted_occurrences);

    // Delete old hourly rollups
    let hourly_cutoff = (Utc::now() - Duration::days(config.retention_days_hourly_rollups))
        .to_rfc3339();
    let deleted_hourly = models::rollup::delete_hourly_before(pool, &hourly_cutoff)?;
    tracing::info!("Deleted {} old hourly rollups", deleted_hourly);

    // Vacuum on Sundays
    if Utc::now().format("%u").to_string() == "7" {
        let conn = pool.get()?;
        conn.execute_batch("VACUUM")?;
        tracing::info!("Database vacuumed");
    }

    Ok(())
}
