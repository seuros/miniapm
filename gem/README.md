# MiniAPM Ruby Client

A lightweight, zero-dependency APM client for Rails applications. Exports traces in OTLP format, captures errors, and provides comprehensive instrumentation.

**Website:** [miniapm.com](https://miniapm.com)

## Features

- **OTLP Compatible**: Exports traces in OpenTelemetry Protocol format
- **Error Tracking**: Automatic exception capture with fingerprinting
- **W3C Trace Context**: Distributed tracing across microservices
- **Zero Runtime Dependencies**: Uses only Ruby stdlib
- **Auto-instrumentation**: Detects and instruments installed gems
- **Non-blocking**: Async batched sending never blocks requests

## Supported Instrumentations

| Category | Library | Method |
|----------|---------|--------|
| **Rails** | ActionController, ActionView | ActiveSupport::Notifications |
| **Database** | ActiveRecord | ActiveSupport::Notifications |
| **Background Jobs** | ActiveJob, SolidQueue | ActiveSupport::Notifications |
| **Background Jobs** | Sidekiq | Server Middleware |
| **Cache** | Rails Cache | ActiveSupport::Notifications |
| **HTTP Clients** | Net::HTTP | Monkey-patch |
| **HTTP Clients** | HTTParty | Monkey-patch |
| **HTTP Clients** | Faraday | Auto-injected Middleware |
| **Search** | Elasticsearch | Monkey-patch |
| **Search** | OpenSearch | Monkey-patch |
| **Search** | Searchkick | ActiveSupport::Notifications |
| **Redis** | redis-client | Middleware |
| **Redis** | redis (legacy) | Monkey-patch |

## Installation

Add to your Gemfile:

```ruby
gem 'miniapm'
```

Then run:

```bash
bundle install
rails generate miniapm:install
```

## Configuration

Set environment variables:

```bash
export MINI_APM_URL="http://your-miniapm-server:3000"
export MINI_APM_API_KEY="your_project_api_key"
```

Or configure in `config/initializers/miniapm.rb`:

```ruby
MiniAPM.configure do |config|
  # Required
  config.endpoint = ENV["MINI_APM_URL"]
  config.api_key = ENV["MINI_APM_API_KEY"]

  # Service identification
  config.service_name = "my-rails-app"
  config.environment = Rails.env

  # Sampling (0.0 to 1.0)
  config.sample_rate = 1.0

  # Batching
  config.batch_size = 100
  config.flush_interval = 5.0

  # Configure instrumentations
  config.instrument :activerecord, log_sql: true
  config.instrument :redis, enabled: false

  # Error filtering
  config.ignored_exceptions = ["ActionController::RoutingError"]
  config.filter_parameters = [:password, :token]

  # Disable in test
  config.enabled = !Rails.env.test?
end
```

## Manual Instrumentation

Create custom spans:

```ruby
MiniAPM.span("process_order", category: :internal) do |span|
  span.add_attribute("order.id", order.id)
  span.add_attribute("order.total", order.total)

  process_order(order)
end
```

Report errors manually:

```ruby
begin
  risky_operation
rescue => e
  MiniAPM.record_error(e, context: {
    user_id: current_user.id,
    params: { order_id: params[:id] }
  })
  raise
end
```

## Distributed Tracing

MiniAPM automatically propagates trace context using W3C Trace Context headers. When making HTTP requests with instrumented clients (Net::HTTP, HTTParty, Faraday), the `traceparent` header is automatically injected.

For incoming requests, MiniAPM extracts the trace context from the `traceparent` header to continue the trace.

## Testing

Disable MiniAPM in tests:

```ruby
# config/initializers/miniapm.rb
config.enabled = !Rails.env.test?
```

Or use the test helpers:

```ruby
require 'miniapm/testing'

RSpec.describe "MyFeature", :miniapm do
  it "tracks spans" do
    perform_action

    expect(MiniAPM::Testing.recorded_spans).to include(
      having_attributes(name: /process_action/)
    )
  end
end
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `endpoint` | `http://localhost:3000` | MiniAPM server URL |
| `api_key` | `nil` | API key for authentication |
| `service_name` | `rails-app` | Service identifier |
| `environment` | `Rails.env` | Deployment environment |
| `sample_rate` | `1.0` | Sampling rate (0.0 to 1.0) |
| `batch_size` | `100` | Max spans per batch |
| `flush_interval` | `5.0` | Seconds between flushes |
| `max_queue_size` | `10000` | Max queued items |
| `enabled` | `true` | Enable/disable tracing |
| `auto_start` | `true` | Start on Rails boot |

## Requirements

- Ruby 3.0+
- Rails 7.0+ (optional, for auto-setup)

## License

MIT

---

[Documentation](https://miniapm.com/docs) | [Source Code](https://github.com/miniapm/miniapm-ruby)
