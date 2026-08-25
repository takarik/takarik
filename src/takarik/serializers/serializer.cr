require "json"

module Takarik
  module JSONAPI
    # Derive a JSON-API resource type from a class name:
    # Models::BlogPost -> blog_posts (naive pluralization, override via #type)
    def self.type_for(klass : Class) : String
      name = klass.name.split("::").last.underscore

      if name.ends_with?("s") || name.ends_with?("x") || name.ends_with?("z") ||
         name.ends_with?("ch") || name.ends_with?("sh")
        "#{name}es"
      elsif name.ends_with?("y") && name.size > 1 && !name[-2].in?('a', 'e', 'i', 'o', 'u')
        "#{name[0...-1]}ies"
      else
        "#{name}s"
      end
    end
  end

  # Include this in models that should be auto-discoverable by registered serializers:
  #
  # ```
  # class User
  #   include Takarik::Resource
  #   ...
  # end
  # ```
  module Resource
  end

  # Non-generic ancestor so the registry can hold any serializer class.
  abstract class BaseSerializer
    abstract def serialize : ::JSON::Any
    abstract def to_json_api : ::JSON::Any
  end

  # Generic serializer base. Subclass it bound to your model:
  #
  # ```
  # class UserSerializer < Takarik::Serializer(User)
  #   def serialize
  #     ::JSON::Any.new({
  #       "id"    => ::JSON::Any.new(id),
  #       "name"  => ::JSON::Any.new(object.name),
  #     })
  #   end
  # end
  # ```
  #
  # Register it once and `render json: @user` picks it up automatically:
  #
  # ```
  # Takarik::Serializers.register(UserSerializer)
  # ```
  abstract class Serializer(T) < BaseSerializer
    getter object : T

    def initialize(@object : T)
    end

    # Plain JSON representation. Override in subclasses.
    # Default: builds an object from the model's readable attributes (getters
    # matching its instance variables).
    def serialize : ::JSON::Any
      {% begin %}
        hash = {
          {% for ivar in T.instance_vars %}
            {% if T.has_method?(ivar.name) %}
              {{ivar.name.stringify}} => Takarik::Serializers.to_json_any(object.{{ivar.name}}),
            {% end %}
          {% end %}
        } of String => ::JSON::Any
        ::JSON::Any.new(hash)
      {% end %}
    end

    # JSON-API resource object: {id, type, attributes}.
    # Override `attributes`, `id` or `type` for customization.
    def to_json_api : ::JSON::Any
      ::JSON::Any.new(resource_object)
    end

    def resource_object : Hash(String, ::JSON::Any)
      obj = {
        "type" => ::JSON::Any.new(type),
      } of String => ::JSON::Any
      obj["id"] = ::JSON::Any.new(id) if id
      obj["attributes"] = ::JSON::Any.new(attributes)
      obj
    end

    # Attributes exposed in the JSON-API document. Defaults to whatever
    # `serialize` produced (if it is an object); override for precision.
    def attributes : Hash(String, ::JSON::Any)
      serialized = serialize
      serialized.as_h? || {} of String => ::JSON::Any
    end

    def id : String?
      obj = object
      if obj.responds_to?(:id)
        value = obj.id
        value.nil? ? nil : value.to_s
      end
    end

    def type : String
      JSONAPI.type_for(object.class)
    end

    # --- Deserialization ---------------------------------------------------

    # Extract an attribute hash from a request payload. The plain flavor
    # expects the payload itself to be the attribute object.
    def self.deserialize(payload : ::JSON::Any) : Hash(String, ::JSON::Any)
      payload.as_h? || raise ArgumentError.new("Expected a JSON object for deserialization")
    end

    def self.deserialize_id(payload : ::JSON::Any) : String?
      nil
    end
  end
end
