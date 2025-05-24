require "./store"

module Takarik
  module Session
    # In-memory session store for development and testing
    class MemoryStore < Store
      @sessions : Hash(String, {data: Hash(String, JSON::Any), created_at: Time})
      @max_age : Time::Span

      def initialize(@max_age : Time::Span = 24.hours)
        @sessions = {} of String => {data: Hash(String, JSON::Any), created_at: Time}
      end

      def read(session_id : String) : Hash(String, JSON::Any)?
        cleanup_expired
        if session = @sessions[session_id]?
          session[:data]
        else
          nil
        end
      end

      def write(session_id : String, data : Hash(String, JSON::Any)) : Bool
        cleanup_expired
        @sessions[session_id] = {data: data, created_at: Time.utc}
        true
      rescue
        false
      end

      def delete(session_id : String) : Bool
        @sessions.delete(session_id) ? true : false
      end

      def exists?(session_id : String) : Bool
        cleanup_expired
        @sessions.has_key?(session_id)
      end

      def cleanup : Int32
        cleanup_expired
      end

      private def cleanup_expired : Int32
        cutoff = Time.utc - @max_age
        initial_count = @sessions.size

        @sessions.reject! do |_, session|
          session[:created_at] < cutoff
        end

        initial_count - @sessions.size
      end

      # Additional methods for debugging/monitoring
      def size : Int32
        cleanup_expired
        @sessions.size
      end

      def clear : Bool
        @sessions.clear
        true
      end
    end
  end
end
