require "json"

module Takarik
  module Session
    # Abstract base class for session storage backends
    abstract class Store
      abstract def read(session_id : String) : Hash(String, JSON::Any)?
      abstract def write(session_id : String, data : Hash(String, JSON::Any)) : Bool
      abstract def delete(session_id : String) : Bool
      abstract def exists?(session_id : String) : Bool
      abstract def cleanup : Int32  # Returns number of cleaned up sessions

      # Generate a secure session ID
      def generate_session_id : String
        Random::Secure.hex(32)
      end
    end
  end
end
