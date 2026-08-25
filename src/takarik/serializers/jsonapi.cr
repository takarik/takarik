require "json"

module Takarik
  module JSONAPI
    # JSON-API compliant serializer. Subclass it and define the exposed
    # attributes; serialization/deserialization follows jsonapi.org:
    #
    # ```
    # class UserSerializer < Takarik::JSONAPI::Serializer(User)
    #   def type
    #     "users" # optional, derived from the class name otherwise
    #   end
    #
    #   def attributes : Hash(String, ::JSON::Any)
    #     {
    #       "email"      => ::JSON::Any.new(object.email),
    #       "created_at" => ::JSON::Any.new(object.created_at.to_s),
    #     }
    #   end
    # end
    # ```
    #
    # Serializes to `{ "data": { "id": ..., "type": ..., "attributes": ... } }`
    abstract class Serializer(T) < Takarik::Serializer(T)
      def to_json_api : ::JSON::Any
        ::JSON::Any.new({
          "data" => ::JSON::Any.new(resource_object),
        })
      end

      def attributes : Hash(String, ::JSON::Any)
        {} of String => ::JSON::Any
      end

      # Optional relationships hook — return a hash of relationship documents.
      def relationships : Hash(String, ::JSON::Any)
        {} of String => ::JSON::Any
      end

      def resource_object : Hash(String, ::JSON::Any)
        obj = super
        rels = relationships
        obj["relationships"] = ::JSON::Any.new(rels) unless rels.empty?
        obj
      end

      def self.deserialize(payload : ::JSON::Any) : Hash(String, ::JSON::Any)
        data = payload.as_h?.try(&.["data"]?)
        attrs = data.try(&.as_h?).try(&.["attributes"]?)

        unless attrs && attrs.as_h?
          raise ArgumentError.new("Invalid JSON-API payload: missing data.attributes")
        end

        attrs.as_h
      end

      def self.deserialize_id(payload : ::JSON::Any) : String?
        payload.as_h?.try(&.["data"]?).try(&.as_h?).try(&.["id"]?).try(&.as_s?)
      end
    end
  end
end
