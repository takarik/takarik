require "http"
require "radix"
require "log"
require "./base_controller"

alias RouteInfo = {http_method: String, controller: Takarik::BaseController.class, action: Symbol}

module Takarik
  class Router
    getter radix_tree : Radix::Tree(Hash(String, RouteInfo))

    @@instance : self = self.new

    def self.instance
      @@instance
    end

    def self.define(&block : Router -> Nil)
      yield self.instance
    end

    macro define_standard_http_routes
      {% for verb in ["get", "post", "put", "patch", "delete"] %}
        def {{verb.id}}(path_pattern : String, controller : Takarik::BaseController.class, action : Symbol)
          add_route({{verb.upcase}}, path_pattern, controller, action)
        end
      {% end %}
    end

    define_standard_http_routes

    def initialize
      @radix_tree = Radix::Tree(Hash(String, RouteInfo)).new
    end

    def match(request_method : String, request_path : String) : {RouteInfo, Hash(String, String)}?
      radix_result = @radix_tree.find(request_path)

      if radix_result.found?
        routes_at_path = radix_result.payload # Hash of HTTP method -> RouteInfo
        params = radix_result.params || {} of String => String

        Log.debug { "Radix found path: #{request_path}. Methods available: #{routes_at_path.keys.join(", ")}" }

        if route_info = routes_at_path[request_method.upcase]?
          Log.debug { "Method matched. Route: #{route_info}, Params: #{params}" }
          return {route_info, params}
        end

        Log.debug { "Path found, but no route matched HTTP method: #{request_method}" }
      else
        Log.debug { "No route found in Radix tree for path: #{request_path}" }
      end

      nil # No match found
    end

    private def add_route(method : String | Symbol, path_pattern : String, controller : Takarik::BaseController.class, action : Symbol)
      http_method = method.to_s.upcase

      route_info = RouteInfo.new(
        http_method: http_method,
        controller: controller,
        action: action,
      )

      # Add to Radix tree
      result = @radix_tree.find(path_pattern)

      if result.found?
        # Path exists, update the methods hash
        routes_hash = result.payload
        routes_hash[http_method] = route_info
      else
        # New path, create a new hash
        routes_hash = {http_method => route_info}
        @radix_tree.add(path_pattern, routes_hash)
      end

      Log.debug { "Added route: #{http_method} #{path_pattern} -> #{controller.name}##{action}" }

      route_info
    end
  end
end
