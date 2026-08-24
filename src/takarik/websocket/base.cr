require "http/web_socket"
require "log"

module Takarik
  # Abstract base class for WebSocket controllers.
  #
  # Subclass this and override the lifecycle hooks to handle WebSocket traffic:
  #
  # ```
  # class ChatSocket < Takarik::WebSocket
  #   def on_open
  #     send("Welcome to room #{params["room"]}")
  #   end
  #
  #   def on_message(message : String)
  #     send("echo: #{message}")
  #   end
  # end
  #
  # # routes.cr
  # websocket "/chat/:room", ChatSocket
  # ```
  abstract class WebSocket
    getter socket : ::HTTP::WebSocket
    getter route_params : Hash(String, String)

    @hub_channels : Hash(Hub, Set(String))

    def initialize(@socket : ::HTTP::WebSocket, @route_params : Hash(String, String))
      @hub_channels = {} of Hub => Set(String)
    end

    # The default application-wide hub.
    def hub : Hub
      Hub.default
    end

    # Join this socket to a channel on the default hub (or an explicit one).
    def join(channel : String)
      hub.join(channel, self)
    end

    def join(channel : String, on target_hub : Hub)
      target_hub.join(channel, self)
    end

    # Leave a channel on the default hub (or an explicit one).
    def leave(channel : String)
      hub.leave(channel, self)
    end

    def leave(channel : String, on target_hub : Hub)
      target_hub.leave(channel, self)
    end

    # Lifecycle hooks — override in subclasses
    def on_open
    end

    def on_message(message : String)
    end

    def on_binary(message : Bytes)
    end

    def on_close(code : Int32 | ::HTTP::WebSocket::CloseCode?, message : String?)
    end

    def on_ping(message : String)
      socket.pong(message)
    end

    def on_pong(message : String)
    end

    # Send a text message to the client
    def send(message : String)
      socket.send(message)
    end

    # Send binary data to the client
    def send(data : Bytes)
      socket.send(data)
    end

    def stream(data : Bytes, final_frame : Bool = true)
      socket.stream(final_frame) { |io| io.write(data) }
    end

    # Close the connection
    def close(code : Int32 = 1000, message : String? = nil)
      socket.close(code.to_u16, message)
    rescue ex
      Log.warn(exception: ex) { "Error while closing WebSocket" }
    end

    # Whether the connection has been closed by either side
    def closed?
      socket.closed?
    end

    # Internal: wires up the callbacks and starts reading frames.
    # Called by the framework after a successful handshake.
    def __start__
      socket.on_message { |message| on_message(message) }
      socket.on_binary { |data| on_binary(data) }
      socket.on_close { |code, message| on_close(code, message) }
      socket.on_ping { |message| on_ping(message) }
      socket.on_pong { |message| on_pong(message) }

      begin
        on_open
        socket.run
        Log.debug { "WebSocket connection ended" }
      rescue ex
        Log.error(exception: ex) { "Unhandled error in WebSocket connection" }
      ensure
        # Drop the socket from all hubs it joined
        begin
          cleanup_hubs
          socket.close unless socket.closed?
        rescue
          # ignore errors during cleanup
        end
      end
    end

    # Internal: channel bookkeeping used by Hub
    def __track__channel__(target_hub : Hub, channel : String)
      (@hub_channels[target_hub] ||= Set(String).new) << channel
    end

    def __untrack__channel__(target_hub : Hub, channel : String)
      if channels = @hub_channels[target_hub]?
        channels.delete(channel)
        @hub_channels.delete(target_hub) if channels.empty?
      end
    end

    private def cleanup_hubs
      @hub_channels.each do |target_hub, channels|
        channels.each { |channel| target_hub.leave(channel, self) }
      end
      @hub_channels.clear
    end
  end
end
