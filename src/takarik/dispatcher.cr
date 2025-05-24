require "http/server"
require "./router"
require "./base_controller"
require "./callbacks"
require "./configuration"
require "log"

module Takarik
  class Dispatcher
    getter router : Router

    def initialize(@router)
    end

    def dispatch(context : HTTP::Server::Context)
      request = context.request
      response = context.response
      start_time = Time.monotonic

      # Try to serve static files first if enabled
      if Takarik.config.serve_static_files?
        if static_handler = Takarik.config.static_file_handler
          if StaticFileHandler.static_path?(request.path, Takarik.config.static_url_prefix)
            if static_handler.call(context)
              log_request(request, response, Time.monotonic - start_time)
              return
            end
          end
        end
      end

      matched = router.match(request.method.to_s, request.path.not_nil!)

      unless matched
        response.status = :not_found
        response.content_type = "text/plain"
        response.puts "Not Found"
        log_request(request, response, Time.monotonic - start_time)
        return
      end

      route_info, params = matched
      controller_class = route_info[:controller]
      action = route_info[:action]

      Log.debug { "Controller class from route: #{controller_class}, Action: #{action}" }

      Log.debug { "Instantiating controller: #{controller_class.name}" }
      controller_instance = controller_class.new(context, params)
      continue_processing = true

      begin
        if controller_instance.responds_to?(:run_before_action)
          continue_processing = controller_instance.run_before_action(action)
        end

        if continue_processing && !response.closed?
          Log.debug { "Calling action: #{controller_class.name}##{action}" }

          controller_instance.dispatch(action)

          if controller_instance.responds_to?(:run_after_action)
            controller_instance.run_after_action(action)
          end
        else
          Log.debug { "Processing halted by before_action for #{controller_class.name}##{action}" }
        end
      rescue ex
        response.status = :internal_server_error
        response.content_type = "text/plain"
        response.puts "Internal Server Error\n\n#{ex.message}\n#{ex.backtrace.join("\n")}"
        Log.error(exception: ex) { "Error processing request: #{request.method} #{request.path}" }
      ensure
        log_request(request, response, Time.monotonic - start_time)
      end
    end

    private def log_request(request, response, duration)
      Log.info { "[#{request.method}] #{request.path} - #{response.status.code} (#{duration.total_milliseconds.round(2)}ms)" }
    end
  end
end
