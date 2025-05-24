require "./store"
require "json"

module Takarik
  module Session
    # Main session class that provides the API for controllers
    class Instance
      getter id : String
      @store : Store
      @data : Hash(String, JSON::Any)
      @flash : Hash(String, JSON::Any)
      @loaded : Bool
      @dirty : Bool

      def initialize(@store : Store, session_id : String? = nil)
        @id = session_id || @store.generate_session_id
        @data = {} of String => JSON::Any
        @flash = {} of String => JSON::Any
        @loaded = false
        @dirty = false
      end

      # Load session data from store
      def load : Bool
        return true if @loaded

        if stored_data = @store.read(@id)
          @data = stored_data.clone
          # Extract flash data if it exists
          if flash_data = @data.delete("_flash")
            @flash = flash_data.as_h.transform_keys(&.to_s).transform_values(&.as(JSON::Any))
          end
        end

        @loaded = true
        true
      rescue
        @loaded = true
        false
      end

      # Save session data to store
      def save : Bool
        # Add current flash to data for next request
        unless @flash.empty?
          @data["_flash"] = JSON::Any.new(@flash.transform_keys(&.to_s))
        end

        result = @store.write(@id, @data)
        @dirty = false if result
        result
      rescue
        false
      end

      # Get session value
      def [](key : String) : JSON::Any?
        load
        @data[key]?
      end

      # Set session value
      def []=(key : String, value) : JSON::Any
        load
        json_value = convert_to_json_any(value)
        @data[key] = json_value
        @dirty = true
        json_value
      end

      # Get session value with type conversion
      def get(key : String, default = nil)
        load
        @data[key]? || convert_to_json_any(default)
      end

      # Delete session value
      def delete(key : String) : JSON::Any?
        load
        if value = @data.delete(key)
          @dirty = true
          value
        end
      end

      # Check if session has key
      def has_key?(key : String) : Bool
        load
        @data.has_key?(key)
      end

      # Get all session keys
      def keys : Array(String)
        load
        @data.keys
      end

      # Clear all session data
      def clear : Bool
        load
        @data.clear
        @flash.clear
        @dirty = true
        true
      end

      # Check if session is empty
      def empty? : Bool
        load
        @data.empty?
      end

      # Check if session has been modified
      def dirty? : Bool
        @dirty
      end

      # Flash message methods
      def flash : FlashHash
        load
        FlashHash.new(@flash)
      end

      # Destroy session completely
      def destroy : Bool
        clear
        @store.delete(@id)
      end

      # Convert various types to JSON::Any
      private def convert_to_json_any(value)
        case value
        when JSON::Any
          value
        when String
          JSON::Any.new(value)
        when Int32, Int64
          JSON::Any.new(value.to_i64)
        when Float32, Float64
          JSON::Any.new(value.to_f)
        when Bool
          JSON::Any.new(value)
        when Array
          JSON::Any.new(value.map { |item| convert_to_json_any(item) })
        when Hash
          hash_result = {} of String => JSON::Any
          value.each { |k, v| hash_result[k.to_s] = convert_to_json_any(v) }
          JSON::Any.new(hash_result)
        when Nil
          JSON::Any.new(nil)
        else
          # For other types, try to convert to string
          JSON::Any.new(value.to_s)
        end
      end
    end

    # Flash message helper class
    class FlashHash
      def initialize(@flash : Hash(String, JSON::Any))
      end

      # Get flash message
      def [](key : String) : JSON::Any?
        @flash[key]?
      end

      # Set flash message
      def []=(key : String, value) : JSON::Any
        json_value = convert_to_json_any(value)
        @flash[key] = json_value
        json_value
      end

      # Common flash message methods
      def notice : String?
        self["notice"].try(&.as_s?)
      end

      def notice=(message : String)
        self["notice"] = message
      end

      def alert : String?
        self["alert"].try(&.as_s?)
      end

      def alert=(message : String)
        self["alert"] = message
      end

      def error : String?
        self["error"].try(&.as_s?)
      end

      def error=(message : String)
        self["error"] = message
      end

      # Check if flash has any messages
      def empty? : Bool
        @flash.empty?
      end

      # Get all flash keys
      def keys : Array(String)
        @flash.keys
      end

      # Clear all flash messages
      def clear
        @flash.clear
      end

      private def convert_to_json_any(value)
        case value
        when JSON::Any
          value
        when String
          JSON::Any.new(value)
        when Int32, Int64
          JSON::Any.new(value.to_i64)
        when Float32, Float64
          JSON::Any.new(value.to_f)
        when Bool
          JSON::Any.new(value)
        when Nil
          JSON::Any.new(nil)
        else
          JSON::Any.new(value.to_s)
        end
      end
    end
  end
end
