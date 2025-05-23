require "http/server"
require "json"
require "uri"
require "./views/engine"
require "./callbacks"
require "log"

module Takarik
  abstract class BaseController
    include Callbacks

    property context : HTTP::Server::Context
    property route_params : Hash(String, String)
    @current_action_name : Symbol?

    def initialize(@context : HTTP::Server::Context, @route_params : Hash(String, String))
      @_params = nil
      @current_action_name = nil
    end

    @_params : Hash(String, ::JSON::Any)? = nil

    protected def request : HTTP::Request
      context.request
    end

    protected def response : HTTP::Server::Response
      context.response
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
