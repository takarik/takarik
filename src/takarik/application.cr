require "http/server"
require "./router"
require "./dispatcher"
require "log"

module Takarik
  class Application
    getter router : Router
    getter dispatcher : Dispatcher
    getter host : String
    getter port : Int32

    def initialize(@host = "0.0.0.0", @port = 3000)
      Log.setup_from_env
      Log.info { "Initializing Takarik application..." }

      @router = Router.instance
      @dispatcher = Dispatcher.new(@router)

      Log.info { "Router initialized" }
    end

    def run
      server = HTTP::Server.new do |context|
        begin
          dispatcher.dispatch(context)
        rescue ex
          context.response.status = :internal_server_error
          context.response.content_type = "text/plain"
          context.response.puts "Unhandled Server Error\n\n#{ex.message}"
          Log.fatal(exception: ex) { "Unhandled error during dispatch" }
        ensure
          context.response.close unless context.response.closed?
        end
      end

      server.bind_tcp(host, port)

      Log.info { "Takarik server listening on http://#{host}:#{port}" }
      puts "=> Takarik application starting on http://#{host}:#{port}"
      puts "=> Use Ctrl-C to stop"

      Signal::INT.trap { graceful_shutdown(server) }
      Signal::TERM.trap { graceful_shutdown(server) }

      begin
        server.listen
      rescue ex
        Log.fatal(exception: ex) { "Server failed to start listening" }
        exit 1
      end
    end

    private def graceful_shutdown(server : HTTP::Server)
      Log.info { "Shutting down server..." }
      puts "\nExiting..."
      server.close
      exit 0
    end
  end
end
