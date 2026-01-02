use chrono::{Datelike, Timelike, Utc};

// Hour-of-day multipliers (simulates business hours traffic)
const HOURLY_PATTERN: [f64; 24] = [
    0.2, 0.1, 0.1, 0.1,  // 0-3
    0.1, 0.2, 0.4, 0.6,  // 4-7
    0.8, 1.0, 1.2, 1.3,  // 8-11
    1.1, 1.2, 1.3, 1.2,  // 12-15
    1.1, 1.0, 0.9, 0.8,  // 16-19
    0.7, 0.6, 0.4, 0.3,  // 20-23
];

// Day-of-week multipliers (1=Monday, 7=Sunday)
const DAILY_PATTERN: [f64; 7] = [
    1.0,  // Monday
    1.1,  // Tuesday
    1.1,  // Wednesday
    1.0,  // Thursday
    0.9,  // Friday
    0.7,  // Saturday
    0.6,  // Sunday
];

pub fn traffic_multiplier() -> f64 {
    let now = Utc::now();
    let hour = now.hour() as usize;
    let weekday = now.weekday().num_days_from_monday() as usize;

    HOURLY_PATTERN[hour] * DAILY_PATTERN[weekday]
}

pub fn traffic_multiplier_for(hour: u32, weekday: u32) -> f64 {
    HOURLY_PATTERN[hour as usize % 24] * DAILY_PATTERN[weekday as usize % 7]
}

/// Simulate latency with log-normal distribution for realistic tail latency
pub fn simulate_latency(base_ms: f64) -> f64 {
    use rand::Rng;
    let mut rng = rand::thread_rng();

    // Box-Muller transform for normal distribution
    let u1: f64 = rng.gen();
    let u2: f64 = rng.gen();
    let normal = (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos();

    // Log-normal: exp(normal * sigma + mu)
    let sigma = 0.5;
    let multiplier = (normal * sigma).exp();

    (base_ms * multiplier).max(1.0)
}

pub fn simulate_db_time(total_ms: f64) -> f64 {
    use rand::Rng;
    let mut rng = rand::thread_rng();

    // DB typically 40-70% of request time
    let ratio = 0.4 + rng.gen::<f64>() * 0.3;
    total_ms * ratio
}

pub fn simulate_view_time(total_ms: f64, db_ms: f64) -> f64 {
    use rand::Rng;
    let mut rng = rand::thread_rng();

    let remaining = total_ms - db_ms;
    remaining * (0.6 + rng.gen::<f64>() * 0.3)
}
