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
    # Auto-register every concrete serializer with the registry, and define a
    # __takarik_entry class method so the serializer can be passed explicitly
    # (`render jsonapi: @user, serializer: UserSerializer`) without any
    # registry lookup. The hook fires for all descendants (including
    # JSONAPI::Serializer subclasses); unbound generic declarations (whose
    # type var is not a TypeNode) and abstract classes are skipped — those are
    # never render targets.
    macro inherited
      {% begin %}
        {% base = @type %}
        {% for _depth in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] %}
          {% if base.type_vars.size == 0 && (sc = base.superclass).is_a?(TypeNode) %}
            {% base = sc %}
          {% end %}
        {% end %}
        {% model = base.type_vars.size == 1 ? base.type_vars[0] : nil %}
        {% unless model.nil? || !model.is_a?(TypeNode) || @type.abstract? %}
          ::Takarik::Serializers.register({{@type}})

          def self.__takarik_entry : ::Takarik::Serializers::Entry
            ::Takarik::Serializers::Entry.new(
              {{@type.stringify}},
              ->(res : Takarik::Resource) { {{@type}}.new(res.as({{model}})).serialize },
              ->(res : Takarik::Resource) { {{@type}}.new(res.as({{model}})).to_json_api },
              ->(res : Takarik::Resource) { ::JSON::Any.new({{@type}}.new(res.as({{model}})).resource_object) },
              ->(payload : ::JSON::Any) { {{@type}}.deserialize(payload) },
              ->(payload : ::JSON::Any) : String? { {{@type}}.deserialize_id(payload) }
            )
          end
        {% end %}
      {% end %}
    end

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
