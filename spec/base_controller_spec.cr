require "./spec_helper"
require "http/server"
require "json"

# Create test controllers for specs
class TestBaseController < Takarik::BaseController
  actions :index, :show, :create, :custom_action

  def index
    render plain: "index action"
  end

  def show
    render json: {"id" => params["id"]}
  end

  def create
    render status: :created
  end

  def custom_action
    render plain: "custom action executed"
  end

  # Public accessors for testing protected methods
  def public_params
    params
  end
end

class InheritedController < TestBaseController
  actions :inherited_action

  def inherited_action
    render plain: "inherited action works"
  end
end

# Helper to create mock HTTP contexts with proper IO setup
def create_test_context(method = "GET", path = "/", body = nil, headers = HTTP::Headers.new, query_string = "")
  # Create request
  request_uri = path
  request_uri += "?#{query_string}" unless query_string.empty?

  body_io = IO::Memory.new
  if body
    body_io.print(body)
    body_io.rewind
  end

  request = HTTP::Request.new(method, request_uri, headers, body_io)

  # Create response with memory output
  response_io = IO::Memory.new
  response = HTTP::Server::Response.new(response_io)

  # Create context
  HTTP::Server::Context.new(request, response)
end

describe Takarik::BaseController do
  describe "initialization" do
    it "initializes with context and route params" do
      context = create_test_context
      route_params = {"id" => "123", "name" => "test"}

      controller = TestBaseController.new(context, route_params)

      controller.context.should eq(context)
      controller.route_params.should eq(route_params)
    end
  end

  describe "#request and #response" do
    it "provides access to request and response objects through context" do
      context = create_test_context("POST", "/test")
      controller = TestBaseController.new(context, {} of String => String)

      controller.context.request.should eq(context.request)
      controller.context.response.should eq(context.response)
      controller.context.request.method.should eq("POST")
      controller.context.request.path.should eq("/test")
    end
  end

  describe "#params" do
    context "with route parameters" do
      it "includes route parameters" do
        context = create_test_context
        route_params = {"id" => "123", "action" => "show"}
        controller = TestBaseController.new(context, route_params)

        params = controller.public_params
        params["id"].as_s.should eq("123")
        params["action"].as_s.should eq("show")
      end
    end

    context "with query parameters" do
      it "includes query parameters" do
        context = create_test_context("GET", "/test", query_string: "name=john&age=25")
        controller = TestBaseController.new(context, {} of String => String)

        params = controller.public_params
        params["name"].as_s.should eq("john")
        params["age"].as_s.should eq("25")
      end
    end

    context "with form-encoded body" do
      it "parses form-urlencoded request body" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        form_body = "name=bob&email=bob%40example.com&age=30"

        context = create_test_context("POST", "/test", form_body, headers)
        controller = TestBaseController.new(context, {} of String => String)

        params = controller.public_params
        params["name"].as_s.should eq("bob")
        params["email"].as_s.should eq("bob@example.com")
        params["age"].as_s.should eq("30")
      end
    end

    context "with mixed parameter sources" do
      it "merges route params and query params" do
        context = create_test_context("GET", "/users/123", query_string: "query_param=from_query")
        route_params = {"id" => "123", "route_param" => "from_route"}
        controller = TestBaseController.new(context, route_params)

        params = controller.public_params
        params["id"].as_s.should eq("123")
        params["route_param"].as_s.should eq("from_route")
        params["query_param"].as_s.should eq("from_query")
      end
    end

    it "memoizes params computation" do
      context = create_test_context
      route_params = {"id" => "123"}
      controller = TestBaseController.new(context, route_params)

      params1 = controller.public_params
      params2 = controller.public_params

      params1.should be(params2) # Same object reference
    end
  end

  describe "#dispatch" do
    it "dispatches to the correct action" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      controller.dispatch(:index)

      controller.context.response.status.should eq(HTTP::Status::OK)
    end

    it "handles actions with parameters" do
      context = create_test_context
      route_params = {"id" => "456"}
      controller = TestBaseController.new(context, route_params)

      controller.dispatch(:show)

      controller.context.response.status.should eq(HTTP::Status::OK)
    end

    it "handles status-only responses" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      controller.dispatch(:create)

      controller.context.response.status.should eq(HTTP::Status::CREATED)
    end

    it "handles custom actions" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      controller.dispatch(:custom_action)

      controller.context.response.status.should eq(HTTP::Status::OK)
    end

    it "returns 404 for unknown actions" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      controller.dispatch(:nonexistent_action)

      controller.context.response.status.should eq(HTTP::Status::NOT_FOUND)
    end
  end

  describe "action macro" do
    it "generates dispatch method with listed actions" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      # Should respond to all defined actions without errors
      controller.dispatch(:index)
      controller.context.response.status.should eq(HTTP::Status::OK)
    end
  end

  describe "inheritance behavior" do
    it "works with inherited controllers" do
      context = create_test_context
      controller = InheritedController.new(context, {} of String => String)

      controller.dispatch(:inherited_action)

      controller.context.response.status.should eq(HTTP::Status::OK)
    end
  end

  describe "protected method access" do
    it "properly encapsulates protected methods" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      # We can access params through our public accessor
      params = controller.public_params
      params.should be_a(Hash(String, JSON::Any))
    end
  end
end
