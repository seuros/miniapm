# frozen_string_literal: true

module MiniAPM
  module Instrumentations
    module Rails
      class Controller < Base
        class << self
          def install!
            return if installed?
            mark_installed!

            # Subscribe to controller processing
            subscribe("process_action.action_controller") do |event|
              handle_process_action(event)
            end

            # Subscribe to view rendering
            subscribe("render_template.action_view") do |event|
              handle_render_template(event)
            end

            subscribe("render_partial.action_view") do |event|
              handle_render_partial(event)
            end

            subscribe("render_collection.action_view") do |event|
              handle_render_collection(event)
            end

            subscribe("render_layout.action_view") do |event|
              handle_render_layout(event)
            end
          end

          private

          def handle_process_action(event)
            span = Context.current_span
            return unless span&.root?

            payload = event.payload

            # Update root span with controller info
            span.add_attribute("http.method", payload[:method])
            span.add_attribute("http.route", "#{payload[:controller]}##{payload[:action]}")
            span.add_attribute("rails.controller", payload[:controller])
            span.add_attribute("rails.action", payload[:action])
            span.add_attribute("rails.format", payload[:format]) if payload[:format]

            if payload[:status]
              span.add_attribute("http.status_code", payload[:status])
              span.set_error("HTTP #{payload[:status]}") if payload[:status] >= 500
            end

            # Add timing breakdown
            if payload[:db_runtime]
              span.add_attribute("rails.db_runtime_ms", payload[:db_runtime].round(2))
            end

            if payload[:view_runtime]
              span.add_attribute("rails.view_runtime_ms", payload[:view_runtime].round(2))
            end

            # Record exception if present
            if payload[:exception_object]
              span.record_exception(payload[:exception_object])
            end
          end

          def handle_render_template(event)
            record_view_span("render_template", event)
          end

          def handle_render_partial(event)
            record_view_span("render_partial", event)
          end

          def handle_render_collection(event)
            record_view_span("render_collection", event)
          end

          def handle_render_layout(event)
            record_view_span("render_layout", event)
          end

          def record_view_span(type, event)
            return unless MiniAPM.enabled?
            return unless Context.current_trace

            payload = event.payload
            template = payload[:identifier] || payload[:virtual_path] || "unknown"

            # Clean up template path
            if defined?(::Rails.root) && ::Rails.root
              template = template.sub(::Rails.root.to_s + "/", "")
            end

            template_name = File.basename(template)

            attributes = {
              "rails.template" => template,
              "rails.template.type" => type
            }

            if payload[:layout]
              attributes["rails.layout"] = payload[:layout]
            end

            if payload[:count]
              attributes["rails.collection.count"] = payload[:count]
            end

            span = create_span_from_event(
              event,
              name: "#{type} #{template_name}",
              category: :view,
              attributes: attributes
            )

            record_span(span)
          end
        end
      end
    end
  end
end

# Auto-install when loaded
MiniAPM::Instrumentations::Rails::Controller.install!
