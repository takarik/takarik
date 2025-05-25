require "http/server"
require "json"
require "uri"
require "./views/engine"
require "./callbacks"
require "./session/session"
require "./configuration"
require "log"

module Takarik
  abstract class BaseController
    include Callbacks

    property context : HTTP::Server::Context
    property route_params : Hash(String, String)
    @current_action_name : Symbol?
    @session : Session::Instance?

    def initialize(@context : HTTP::Server::Context, @route_params : Hash(String, String))
      @_params = nil
      @current_action_name = nil
      @session = nil
    end

    @_params : Hash(String, ::JSON::Any)? = nil

    protected def request : HTTP::Request
      context.request
    end

    protected def response : HTTP::Server::Response
      context.response
    end

    # Session access
    protected def session : Session::Instance
      return @session.not_nil! if @session

      config = Takarik.config
      return create_null_session unless config.sessions_enabled?

      store = config.session_store.not_nil!
      session_id = get_session_id_from_cookie

      @session = Session::Instance.new(store, session_id)
      @session.not_nil!
    end

    # Flash messages shortcut
    protected def flash
      session.flash
    end

    private def get_session_id_from_cookie : String?
      config = Takarik.config
      cookie_name = config.session_cookie_name

      # Parse cookies from request
      if cookie_header = request.headers["Cookie"]?
        cookie_header.split(';').each do |cookie_part|
          name, _, value = cookie_part.partition('=')
          name = name.strip
          if name == cookie_name
            return URI.decode(value.strip)
          end
        end
      end

      nil
    end

    private def create_null_session : Session::Instance
      # Create a null session that doesn't persist anything
      null_store = Session::MemoryStore.new(0.seconds)  # Immediate expiry
      Session::Instance.new(null_store)
    end

    protected def params : Hash(String, ::JSON::Any)
      @_params ||= begin
        merged_params = {} of String => ::JSON::Any

        route_params.each { |k, v| merged_params[k] = ::JSON::Any.new(v) }
        request.query_params.each { |k, v| merged_params[k] = ::JSON::Any.new(v) }

        body = request.body
        if body
          content_type = request.headers["Content-Type"]?.to_s.split(';').first.try(&.strip)
          case content_type
          when .ends_with?("json")
            begin
              json_body = body.gets_to_end
              if json_body.bytesize > 0
                parsed_body = ::JSON.parse(json_body)
                if parsed_body.is_a?(Hash)
                  parsed_body.as(Hash).each { |k, v| merged_params[k.to_s] = v }
                else
                  Log.warn { "JSON body root is not an object, cannot merge into params." }
                end
              end
            rescue ex : ::JSON::ParseException
              Log.warn(exception: ex) { "Failed to parse JSON request body" }
            end
          when "application/x-www-form-urlencoded"
            begin
              form_body = body.gets_to_end
              if form_body.bytesize > 0
                URI::Params.parse(form_body).each { |k, v| merged_params[k] = ::JSON::Any.new(v) }
              end
            rescue ex : ArgumentError
              Log.warn(exception: ex) { "Failed to parse form-urlencoded request body" }
            end
          end
        end

        merged_params
      end
    end

    protected def render(view : Symbol? = nil, locals : Hash(Symbol | String, ::JSON::Any) = {} of Symbol => ::JSON::Any, layout : Symbol? = nil, content_type = "text/html")
      engine = Takarik.config.view_engine
      unless engine
        raise "No view engine configured. Set Takarik.config.view_engine."
      end

      if view.nil?
        unless current_view_name = @current_action_name
          raise "Current action name is not set, cannot infer view name."
        end
        view = current_view_name
      end

      response.content_type = content_type
      response.print engine.render(self, view, locals, layout)
    end

    protected def render(plain text : String, content_type = "text/plain")
      response.content_type = content_type
      response.print text
    end

    protected def render(status code : Int | Symbol)
      http_status = code.is_a?(Symbol) ? HTTP::Status.parse(code.to_s) : HTTP::Status.new(code)
      response.status = http_status
    end

    protected def render(json data : T) forall T
      response.content_type = "application/json"
      data.to_json(response)
    end

    protected def head(status : Int | Symbol)
      render(status: status)
    end

    # Helper method to create locals hash with automatic JSON::Any conversion
    protected def locals(**args)
      result = {} of Symbol | String => ::JSON::Any
      args.each do |key, value|
        result[key.to_s] = convert_to_json_any(value)
      end
      result
    end

    # Overload for hash input
    protected def locals(hash : Hash)
      result = {} of Symbol | String => ::JSON::Any
      hash.each do |key, value|
        result[key.to_s] = convert_to_json_any(value)
      end
      result
    end

    # Convert various types to JSON::Any
    private def convert_to_json_any(value)
      case value
      when ::JSON::Any
        value
      when String
        ::JSON::Any.new(value)
      when Int32, Int64
        ::JSON::Any.new(value.to_i64)
      when Float32, Float64
        ::JSON::Any.new(value.to_f64)
      when Bool
        ::JSON::Any.new(value)
      when Array
        ::JSON::Any.new(value.map { |item| convert_to_json_any(item) })
      when Hash
        hash_result = {} of String => ::JSON::Any
        value.each { |k, v| hash_result[k.to_s] = convert_to_json_any(v) }
        ::JSON::Any.new(hash_result)
      when Nil
        ::JSON::Any.new(nil)
      else
        # For other types, try to convert to string
        ::JSON::Any.new(value.to_s)
      end
    end

    # Redirect to a URL or route
    protected def redirect_to(location : String | URI, status : Symbol | Int32 = :found)
      redirect_status = status.is_a?(Symbol) ? HTTP::Status.parse(status.to_s) : HTTP::Status.new(status)
      response.redirect(location, redirect_status)
    end

    # Redirect to a named route
    protected def redirect_to(route_name : Symbol, params : Hash(String, String | Int32) = {} of String => String | Int32, status : Symbol | Int32 = :found)
      path = Router.path_for(route_name.to_s, params)
      redirect_to(path, status)
    end

    # Redirect back to the referrer, with a fallback URL
    protected def redirect_back(fallback_url : String = "/", status : Symbol | Int32 = :found)
      referrer = request.headers["Referer"]?
      redirect_to(referrer || fallback_url, status)
    end

    # Helper methods for path generation
    protected def url_for(route_name : Symbol, params : Hash(String, String | Int32) = {} of String => String | Int32) : String
      Router.url_for(route_name.to_s, params)
    end

    protected def path_for(route_name : Symbol, params : Hash(String, String | Int32) = {} of String => String | Int32) : String
      Router.path_for(route_name.to_s, params)
    end

    macro actions(*actions)
      def dispatch(action_name : Symbol)
        @current_action_name = action_name

        case action_name
        {% for action in actions %}
        when {{action}}
          {{action.id}}()
        {% end %}
        else
          response.status = :not_found
          response.content_type = "text/plain"
          response.print "Unknown action '#{action_name}' in #{self.class.name}"
        end
      end
    end
  end
end
