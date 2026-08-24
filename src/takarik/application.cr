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

    @websocket_handler : HTTP::Handler?
    @before_upgrade : Proc(HTTP::Server::Context, Bool)?

    def initialize(@host = "0.0.0.0", @port = 3000)
      # Only setup logging if not running tests (CRYSTAL_SPEC env var is set by test suite)
      unless ENV["CRYSTAL_SPEC"]? == "1"
        Log.setup_from_env
      end

      Log.info { "Initializing Takarik application..." }

      @router = Router.instance
      @dispatcher = Dispatcher.new(@router)
      @websocket_handler = nil
      @before_upgrade = nil

      Log.info { "Router initialized" }
    end

    def run
      server = HTTP::Server.new([websocket_handler]) do |context|
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

    # Register a callback that runs before any WebSocket handshake completes.
    # Return true to accept the upgrade, false to reject it with 403 Forbidden.
    # Raising from the block also rejects the upgrade with 403.
    #
    # ```
    # app.on_websocket_upgrade do |context|
    #   authorized?(context.request)
    # end
    # ```
    def on_websocket_upgrade(&block : HTTP::Server::Context -> Bool)
      @before_upgrade = block
    end

    # The WebSocket upgrade handler. Installed in front of normal dispatch by `run`;
    # exposed publicly so it can be tested or embedded in custom server setups.
    def websocket_handler : HTTP::Handler
      @websocket_handler ||= begin
        ws = HTTP::WebSocketHandler.new do |socket, context|
          handle_websocket(socket, context)
        end
        UpgradeGuardHandler.new(@before_upgrade, ws)
      end
    end

    private def handle_websocket(socket : HTTP::WebSocket, context : HTTP::Server::Context)
      request = context.request
      path = request.path.not_nil!

      if matched = @router.match_websocket(path)
        socket_class, params = matched
        Log.debug { "WebSocket upgrade: #{path} -> #{socket_class.name}" }
        socket_instance = socket_class.new(socket, params)
        socket_instance.__start__
      else
        # No WebSocket route matched — reject the handshake.
        Log.warn { "WebSocket request to unregistered path: #{path}" }
        reject_upgrade(context, status: :not_found, message: "No WebSocket endpoint at #{path}")
      end
    end

    private def websocket_upgrade_request?(request : HTTP::Request) : Bool
      request.headers["Upgrade"]?.try(&.downcase) == "websocket"
    end

    private def upgrade_allowed?(context : HTTP::Server::Context) : Bool
      return false unless Takarik.config.websocket_origin_allowed?(context.request.headers["Origin"]?)

      if hook = @before_upgrade
        begin
          hook.call(context)
        rescue ex
          Log.error(exception: ex) { "before_upgrade hook raised; rejecting upgrade" }
          false
        end
      else
        true
      end
    end

    private def reject_upgrade(context : HTTP::Server::Context, status : HTTP::StatusCode = :forbidden, message : String = "Forbidden")
      response = context.response
      response.status = status
      response.content_type = "text/plain"
      response.puts message
    end

    # Runs before the actual handshake completes so rejections reach the client
    # as a plain HTTP error rather than a completed-but-silent upgrade.
    private class UpgradeGuardHandler
      include HTTP::Handler
      def initialize(@before_upgrade : Proc(HTTP::Server::Context, Bool)?, @ws_handler : HTTP::WebSocketHandler)
      end

      def call(context)
        request = context.request
        is_ws = request.headers["Upgrade"]?.try(&.downcase) == "websocket"

        if is_ws && !allowed?(context)
          Log.warn { "Rejected WebSocket upgrade to #{request.path} (origin: #{request.headers["Origin"]? || "none"})" }
          response = context.response
          response.status = :forbidden
          response.content_type = "text/plain"
          response.puts "Forbidden"
          return
        end

        @ws_handler.call(context)
      end

      private def allowed?(context : HTTP::Server::Context) : Bool
        return false unless Takarik.config.websocket_origin_allowed?(context.request.headers["Origin"]?)

        if hook = @before_upgrade
          begin
            hook.call(context)
          rescue ex
            Log.error(exception: ex) { "before_upgrade hook raised; rejecting upgrade" }
            false
          end
        else
          true
        end
      end
    end

    private def handle_websocket(socket : HTTP::WebSocket, context : HTTP::Server::Context)
      request = context.request

      if matched = @router.match_websocket(request.path.not_nil!)
        socket_class, params = matched
        Log.debug { "WebSocket upgrade: #{request.path} -> #{socket_class.name}" }
        socket_instance = socket_class.new(socket, params)
        socket_instance.__start__
      else
        # No WebSocket route matched — reject the handshake.
        Log.warn { "WebSocket request to unregistered path: #{request.path}" }
        context.response.status = :bad_request
        context.response.content_type = "text/plain"
        context.response.puts "No WebSocket endpoint at #{request.path}"
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
