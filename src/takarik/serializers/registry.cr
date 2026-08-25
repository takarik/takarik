module Takarik
  module Serializers
    private class Entry
      getter name : String
      getter serialize : Proc(Resource, ::JSON::Any)
      getter serialize_jsonapi : Proc(Resource, ::JSON::Any)
      getter serialize_jsonapi_resource : Proc(Resource, ::JSON::Any)
      getter deserialize : Proc(::JSON::Any, Hash(String, ::JSON::Any))
      getter deserialize_id : Proc(::JSON::Any, String?)

      def initialize(@name, @serialize, @serialize_jsonapi, @serialize_jsonapi_resource, @deserialize, @deserialize_id)
      end
    end

    @@flat = {} of String => Entry   # used by `render json:` / resource_attributes
    @@api = {} of String => Entry    # used by `render jsonapi:`

    # Register a serializer for its model type (inferred from the generic arg).
    # Plain serializers (< Takarik::Serializer) serve `render json:` and
    # JSON-API ones (< Takarik::JSONAPI::Serializer) serve `render jsonapi:`.
    # Call this from inside the Takarik::Serializers namespace:
    #
    # ```
    # class User
    #   include Takarik::Resource
    # end
    #
    # class UserSerializer < Takarik::Serializer(User); end
    # class ApiUserSerializer < Takarik::JSONAPI::Serializer(User); end
    #
    # module Takarik::Serializers
    #   register UserSerializer
    #   register ApiUserSerializer
    # end
    # ```
    macro register(serializer)
      {% begin %}
        {% base = serializer.resolve %}
        {% for _depth in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] %}
          {% if base.type_vars.size == 0 %}
            {% sc = base.superclass %}
            {% if sc.is_a?(TypeNode) %}
              {% base = sc %}
            {% end %}
          {% end %}
        {% end %}
        {% unless base.type_vars.size == 1 %}
          {% raise "#{serializer} must inherit from a bound generic serializer (e.g. Serializer(User) or JSONAPI::Serializer(User))" %}
        {% end %}
        {% model = base.type_vars[0] %}
        {% api_chain = false %}
        {% ancestor = serializer.resolve %}
        {% done = false %}
        {% for _depth in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] %}
          {% unless done %}
            {% if ancestor.name.starts_with?("Takarik::JSONAPI::Serializer") %}
              {% api_chain = true %}
              {% done = true %}
            {% else %}
              {% sc = ancestor.superclass %}
              {% if sc.is_a?(TypeNode) %}
                {% ancestor = sc %}
              {% else %}
                {% done = true %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        {% store_name = api_chain ? "api" : "flat" %}
        @@{{store_name.id}}[{{model.stringify}}] = Entry.new(
          {{serializer.stringify}},
          ->(res : Resource) { {{serializer}}.new(res.as({{model}})).serialize },
          ->(res : Resource) { {{serializer}}.new(res.as({{model}})).to_json_api },
          ->(res : Resource) { ::JSON::Any.new({{serializer}}.new(res.as({{model}})).resource_object) },
          ->(payload : ::JSON::Any) { {{serializer}}.deserialize(payload) },
          ->(payload : ::JSON::Any) : String? { {{serializer}}.deserialize_id(payload) }
        )
      {% end %}
    end

    # Lookup for plain JSON serialization (`render json:`)
    def self.entry_for(model_class : Class) : Entry?
      @@flat[model_class.name]?
    end

    # Lookup for JSON-API serialization (`render jsonapi:`)
    def self.entry_api_for(model_class : Class) : Entry?
      @@api[model_class.name]?
    end

    def self.entry_named?(serializer_class_name : String) : Entry?
      @@flat.values.find?({@@api.values.find? { |e| e.name == serializer_class_name }}) do |e|
        e.name == serializer_class_name
      end
    end

    def self.clear!
      @@flat.clear
      @@api.clear
    end

    # Converts common value types to JSON::Any (used by Serializer's default serialization).
    def self.to_json_any(value) : ::JSON::Any
      case value
      when ::JSON::Any then value
      when String      then ::JSON::Any.new(value)
      when Int32       then ::JSON::Any.new(value.to_i64)
      when Int64       then ::JSON::Any.new(value)
      when Float64     then ::JSON::Any.new(value)
      when Float32     then ::JSON::Any.new(value.to_f64)
      when Bool        then ::JSON::Any.new(value)
      when Nil         then ::JSON::Any.new(nil)
      when Enum        then ::JSON::Any.new(value.to_s)
      when Time        then ::JSON::Any.new(value.to_s("%Y-%m-%dT%H:%M:%S%:z"))
      when Array       then ::JSON::Any.new(value.map { |v| to_json_any(v) })
      when Hash        then ::JSON::Any.new(value.map { |k, v| {k.to_s, to_json_any(v)} }.to_h)
      else                  ::JSON::Any.new(value.to_s)
      end
    end
  end
end
