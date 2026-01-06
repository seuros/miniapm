use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};

use crate::DbPool;

#[derive(Deserialize)]
pub struct McpRequest {
    #[allow(dead_code)]
    jsonrpc: String,
    id: serde_json::Value,
    method: String,
    params: Option<serde_json::Value>,
}

#[derive(Serialize)]
pub struct McpResponse {
    jsonrpc: String,
    id: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<McpError>,
}

#[derive(Serialize)]
pub struct McpError {
    code: i32,
    message: String,
}

pub async fn mcp_handler(
    State(pool): State<DbPool>,
    Json(request): Json<McpRequest>,
) -> Result<Json<McpResponse>, StatusCode> {
    let response = handle_request(&pool, request);
    Ok(Json(response))
}

fn handle_request(pool: &DbPool, request: McpRequest) -> McpResponse {
    let result = match request.method.as_str() {
        "initialize" => handle_initialize(),
        "tools/list" => handle_list_tools(),
        "tools/call" => handle_tool_call(pool, request.params),
        _ => Err(format!("Unknown method: {}", request.method)),
    };

    match result {
        Ok(value) => McpResponse {
            jsonrpc: "2.0".to_string(),
            id: request.id,
            result: Some(value),
            error: None,
        },
        Err(e) => McpResponse {
            jsonrpc: "2.0".to_string(),
            id: request.id,
            result: None,
            error: Some(McpError {
                code: -32603,
                message: e,
            }),
        },
    }
}

fn handle_initialize() -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "protocolVersion": "2024-11-05",
        "capabilities": {
            "tools": {}
        },
        "serverInfo": {
            "name": "miniapm",
            "version": "0.1.0"
        }
    }))
}

fn handle_list_tools() -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "tools": [
            {
                "name": "list_errors",
                "description": "List recent errors grouped by fingerprint",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "status": {"type": "string", "enum": ["open", "resolved", "ignored"]},
                        "limit": {"type": "integer", "default": 10}
                    }
                }
            },
            {
                "name": "error_details",
                "description": "Get full details for a specific error",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "integer"}
                    },
                    "required": ["id"]
                }
            },
            {
                "name": "slow_routes",
                "description": "Get slowest routes by average latency",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "period": {"type": "string", "enum": ["24h", "7d", "30d"], "default": "24h"},
                        "limit": {"type": "integer", "default": 10}
                    }
                }
            },
            {
                "name": "system_status",
                "description": "Get overall system health",
                "inputSchema": {
                    "type": "object",
                    "properties": {}
                }
            }
        ]
    }))
}

fn handle_tool_call(
    pool: &DbPool,
    params: Option<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    use crate::models;
    use chrono::{Duration, Utc};

    let params = params.ok_or("Missing params")?;
    let tool_name = params["name"].as_str().ok_or("Missing tool name")?;
    let args = &params["arguments"];

    let result = match tool_name {
        "list_errors" => {
            let status = args["status"].as_str();
            let limit = args["limit"].as_i64().unwrap_or(10);
            let errors =
                models::error::list(pool, None, status, limit).map_err(|e| e.to_string())?;
            serde_json::to_value(errors).map_err(|e| e.to_string())?
        }
        "error_details" => {
            let id = args["id"].as_i64().ok_or("Missing id")?;
            let error = models::error::find(pool, id).map_err(|e| e.to_string())?;
            let occurrences = if error.is_some() {
                models::error::occurrences(pool, id, 5).map_err(|e| e.to_string())?
            } else {
                vec![]
            };
            serde_json::json!({
                "error": error,
                "occurrences": occurrences
            })
        }
        "slow_routes" => {
            let period = args["period"].as_str().unwrap_or("24h");
            let limit = args["limit"].as_i64().unwrap_or(10);
            let since = match period {
                "7d" => Utc::now() - Duration::days(7),
                "30d" => Utc::now() - Duration::days(30),
                _ => Utc::now() - Duration::hours(24),
            };
            let routes =
                models::span::routes_summary(pool, None, &since.to_rfc3339(), None, "avg", limit)
                    .map_err(|e| e.to_string())?;
            serde_json::to_value(routes).map_err(|e| e.to_string())?
        }
        "system_status" => {
            let since_24h = (Utc::now() - Duration::hours(24)).to_rfc3339();
            let requests_24h =
                models::span::count_since(pool, None, &since_24h).map_err(|e| e.to_string())?;
            let errors_24h =
                models::error::count_since(pool, None, &since_24h).map_err(|e| e.to_string())?;
            let latency_stats = models::span::latency_stats_since(pool, None, &since_24h)
                .map_err(|e| e.to_string())?;
            let db_size = crate::db::get_db_size(pool).map_err(|e| e.to_string())?;

            serde_json::json!({
                "requests_24h": requests_24h,
                "errors_24h": errors_24h,
                "error_rate": if requests_24h > 0 { errors_24h as f64 / requests_24h as f64 } else { 0.0 },
                "avg_response_ms": latency_stats.avg_ms,
                "db_size_mb": db_size
            })
        }
        _ => return Err(format!("Unknown tool: {}", tool_name)),
    };

    Ok(serde_json::json!({
        "content": [{
            "type": "text",
            "text": serde_json::to_string_pretty(&result).map_err(|e| e.to_string())?
        }]
    }))
}
