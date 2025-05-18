require "http"
require "radix"
require "log"
require "./base_controller"

alias RouteInfo = {http_method: String, controller: Takarik::BaseController.class, action: Symbol}

module Takarik
  class Router
    getter radix_tree : Radix::Tree(Hash(String, RouteInfo))

    @@instance : self = self.new
    @current_controller : Takarik::BaseController.class | Nil = nil
    @current_resource : String | Nil = nil
    @current_scope : Symbol | Nil = nil

    def self.instance
      @@instance
    end

    def self.define(&block)
      with instance yield
    end

    {% for verb in ["get", "post", "put", "patch", "delete"] %}
      def {{verb.id}}(path_pattern : String, controller : Takarik::BaseController.class, action : Symbol)
        add_route({{verb.upcase}}, path_pattern, controller, action)
      end
    {% end %}

    {% for verb in ["get", "post", "put", "patch", "delete"] %}
      # Support for path strings
      def {{verb.id}}(path_pattern : String, action : Symbol)
        raise "Controller scope required. Use within a controller block." unless @current_controller

        # Check if we're in a collection or member scope
        path_prefix = case @current_scope
        when :collection
          "/#{@current_resource}"
        when :member
          "/#{@current_resource}/:id"
        else
          ""
        end

        # Apply the prefix if needed
        full_path = path_prefix.empty? ? path_pattern : "#{path_prefix}#{path_pattern}"

        add_route({{verb.upcase}}, full_path, @current_controller.not_nil!, action)
      end

      # Rails-style symbol shortcuts
      def {{verb.id}}(action : Symbol)
        raise "Controller scope required. Use within a controller block." unless @current_controller
        raise "Symbol shortcuts can only be used within collection or member blocks" unless @current_scope

        path_prefix = case @current_scope
        when :collection
          "/#{@current_resource}/#{action}"
        when :member
          "/#{@current_resource}/:id/#{action}"
        else
          "/#{action}" # Should never happen due to the check above
        end

        add_route({{verb.upcase}}, path_prefix, @current_controller.not_nil!, action)
      end
    {% end %}

    def initialize
      @radix_tree = Radix::Tree(Hash(String, RouteInfo)).new
    end

    def define(&block)
      with self yield
    end

    def map(controller : Takarik::BaseController.class, &block)
      @current_controller = controller
      with self yield
      @current_controller = nil
    end

    def resources(resource_name : Symbol | String, **options)
      raise "Controller scope required. Use within a controller block." unless @current_controller
      setup_resource_routes(resource_name, @current_controller.not_nil!, options)
    end

    def resources(resource_name : Symbol | String, controller : Takarik::BaseController.class, **options)
      setup_resource_routes(resource_name, controller, options)
    end

    # Version with block
    def resources(resource_name : Symbol | String, **options, &block)
      raise "Controller scope required. Use within a controller block." unless @current_controller
      setup_resource_routes(resource_name, @current_controller.not_nil!, options)

      # Create a resource scope for the block
      resource = resource_name.to_s
      prev_resource = @current_resource
      @current_resource = resource

      # Execute the block in this object's context
      with self yield

      # Restore the previous resource
      @current_resource = prev_resource
    end

    # Version with controller and block
    def resources(resource_name : Symbol | String, controller : Takarik::BaseController.class, **options, &block)
      setup_resource_routes(resource_name, controller, options)

      # Create a resource scope for the block
      resource = resource_name.to_s
      prev_controller = @current_controller
      prev_resource = @current_resource

      @current_controller = controller
      @current_resource = resource

      # Execute the block in this object's context
      with self yield

      # Restore the previous resource
      @current_controller = prev_controller
      @current_resource = prev_resource
    end

    def collection(&block)
      raise "Collection can only be called within a resources block" unless @current_resource
      resource = @current_resource.not_nil!
      prev_scope = @current_scope
      @current_scope = :collection

      with self yield

      @current_scope = prev_scope
    end

    def member(&block)
      raise "Member can only be called within a resources block" unless @current_resource
      resource = @current_resource.not_nil!
      prev_scope = @current_scope
      @current_scope = :member

      with self yield

      @current_scope = prev_scope
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

    def add_route(method : String | Symbol, path_pattern : String, controller : Takarik::BaseController.class, action : Symbol)
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

    private def setup_resource_routes(resource_name : Symbol | String, controller : Takarik::BaseController.class, options)
      raise "Controller parameter is required." unless controller

      resource = resource_name.to_s
      path_prefix = "/#{resource}"

      # Set default actions
      actions = %i(index new create show edit update destroy)

      # Filter actions based on options
      if only = options[:only]?
        only_actions = only.is_a?(Array) ? only : [only.as(Symbol)]
        actions = actions.select { |a| only_actions.includes?(a) }
      elsif except = options[:except]?
        except_actions = except.is_a?(Array) ? except : [except.as(Symbol)]
        actions = actions.reject { |a| except_actions.includes?(a) }
      end

      # Generate routes for each action
      actions.each do |action|
        case action
        when :index
          add_route("GET", path_prefix, controller, :index)
        when :new
          add_route("GET", "#{path_prefix}/new", controller, :new)
        when :create
          add_route("POST", path_prefix, controller, :create)
        when :show
          add_route("GET", "#{path_prefix}/:id", controller, :show)
        when :edit
          add_route("GET", "#{path_prefix}/:id/edit", controller, :edit)
        when :update
          add_route("PUT", "#{path_prefix}/:id", controller, :update)
          add_route("PATCH", "#{path_prefix}/:id", controller, :update)
        when :destroy
          add_route("DELETE", "#{path_prefix}/:id", controller, :destroy)
        end
      end
    end
  end
end
