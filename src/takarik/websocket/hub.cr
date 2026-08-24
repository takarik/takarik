require "./base"

module Takarik
  class WebSocket
    # Coordinates groups of connected WebSockets ("channels").
    #
    # ```
    # class ChatSocket < Takarik::WebSocket
    #   def on_open
    #     join("room:#{route_params["room"]}")
    #   end
    #
    #   def on_message(message : String)
    #     hub.broadcast("room:#{route_params["room"]}", message)
    #   end
    # end
    # ```
    #
    # The hub is fiber-safe: subscriptions and broadcasts can happen from any
    # fiber (e.g. a background task pushing updates to clients).
    class Hub
      @@default : self = new

      def self.default
        @@default
      end

      @mutex : Mutex
      @channels : Hash(String, Set(WebSocket))

      def initialize
        @mutex = Mutex.new
        @channels = {} of String => Set(WebSocket)
      end

      # Subscribe a socket to a channel.
      def join(channel : String, socket : WebSocket)
        @mutex.synchronize do
          (@channels[channel] ||= Set(WebSocket).new) << socket
          socket.__track__channel__(self, channel)
        end
      end

      # Remove a socket from a channel. No-op if not subscribed.
      def leave(channel : String, socket : WebSocket)
        @mutex.synchronize do
          if members = @channels[channel]?
            members.delete(socket)
            @channels.delete(channel) if members.empty?
          end
          socket.__untrack__channel__(self, channel)
        end
      end

      # Remove a socket from every channel it joined on this hub.
      def remove(socket : WebSocket)
        @mutex.synchronize do
          @channels.each_value do |members|
            members.delete(socket)
          end
          @channels.reject! { |_, members| members.empty? }
        end
      end

      # Send a text message to every member of a channel.
      def broadcast(channel : String, message : String)
        each_member(channel) { |socket| socket.send(message) }
      rescue ex
        Log.error(exception: ex) { "Error broadcasting to channel '#{channel}'" }
      end

      # Send binary data to every member of a channel.
      def broadcast_binary(channel : String, data : Bytes)
        each_member(channel) { |socket| socket.send(data) }
      rescue ex
        Log.error(exception: ex) { "Error broadcasting binary to channel '#{channel}'" }
      end

      # Send a text message to every member of every channel.
      def broadcast_all(message : String)
        all_members.each { |socket| socket.send(message) }
      rescue ex
        Log.error(exception: ex) { "Error broadcasting to all channels" }
      end

      # Send a message to a single member of a channel. Returns false when no such member exists.
      def unicast?(channel : String, target : WebSocket, message : String) : Bool
        found = false
        each_member(channel) do |socket|
          next unless socket.same?(target)
          socket.send(message)
          found = true
        end
        found
      end

      def member_count(channel : String) : Int32
        @mutex.synchronize { @channels[channel]?.try(&.size) || 0 }
      end

      def channels : Array(String)
        @mutex.synchronize { @channels.keys }
      end

      private def each_member(channel : String)
        members = @mutex.synchronize { @channels[channel]?.try(&.dup) }
        return unless members
        members.each do |socket|
          begin
            yield socket
          rescue ex
            Log.error(exception: ex) { "Error sending to a WebSocket in '#{channel}', dropping it" }
            leave(channel, socket)
          end
        end
      end

      private def all_members : Array(WebSocket)
        @mutex.synchronize do
          sockets = Set(WebSocket).new
          @channels.each_value { |members| sockets.concat(members) }
          sockets.to_a
        end
      end
    end
  end
end
