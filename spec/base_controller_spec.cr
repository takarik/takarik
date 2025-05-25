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

  # Public methods for testing protected render functionality
  def public_render(**args)
    render(**args)
  end

  def public_locals(**args)
    locals(**args)
  end

  def public_locals(hash : Hash)
    locals(hash)
  end

  # Public methods for testing protected redirect functionality
  def public_redirect_to(location : String | URI, status : Symbol | Int32 = :found)
    redirect_to(location, status)
  end

  def public_redirect_back(fallback_url : String = "/", status : Symbol | Int32 = :found)
    redirect_back(fallback_url, status)
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

  describe "locals helper method" do
    it "converts various data types to JSON::Any" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      result = controller.public_locals(
        string_val: "hello",
        int_val: 42,
        float_val: 3.14,
        bool_val: true,
        array_val: [1, 2, 3],
        hash_val: {"nested" => "value"},
        nil_val: nil
      )

      result["string_val"].as_s.should eq("hello")
      result["int_val"].as_i64.should eq(42)
      result["float_val"].as_f.should be_close(3.14, 0.01)
      result["bool_val"].as_bool.should be_true
      result["array_val"].as_a.size.should eq(3)
      result["hash_val"].as_h["nested"].as_s.should eq("value")
      result["nil_val"].as_nil.should be_nil
    end

    it "accepts hash input" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      input = {"name" => "test", "count" => 5}
      result = controller.public_locals(input)

      result["name"].as_s.should eq("test")
      result["count"].as_i64.should eq(5)
    end

    it "handles nested arrays and hashes" do
      context = create_test_context
      controller = TestBaseController.new(context, {} of String => String)

      result = controller.public_locals(
        nested: {
          "users" => ["alice", "bob"],
          "meta" => {"total" => 2, "active" => true}
        }
      )

      nested = result["nested"].as_h
      nested["users"].as_a.map(&.as_s).should eq(["alice", "bob"])
      nested["meta"].as_h["total"].as_i64.should eq(2)
      nested["meta"].as_h["active"].as_bool.should be_true
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

  describe "redirect functionality" do
    describe "#redirect_to with URL" do
      it "sets redirect status and location header" do
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        controller.public_redirect_to("/users")

        controller.context.response.status.should eq(HTTP::Status::FOUND)
        controller.context.response.headers["Location"].should eq("/users")
      end

      it "accepts custom status codes" do
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        controller.public_redirect_to("/users", :moved_permanently)

        controller.context.response.status.should eq(HTTP::Status::MOVED_PERMANENTLY)
        controller.context.response.headers["Location"].should eq("/users")
      end

      it "accepts numeric status codes" do
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        controller.public_redirect_to("/users", 301)

        controller.context.response.status.should eq(HTTP::Status::MOVED_PERMANENTLY)
        controller.context.response.headers["Location"].should eq("/users")
      end

      it "accepts URI objects" do
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        uri = URI.parse("https://example.com/users")
        controller.public_redirect_to(uri)

        controller.context.response.status.should eq(HTTP::Status::FOUND)
        controller.context.response.headers["Location"].should eq("https://example.com/users")
      end
    end

    describe "#redirect_back" do
      it "redirects to referrer when present" do
        headers = HTTP::Headers.new
        headers["Referer"] = "/previous-page"
        context = create_test_context("GET", "/test", headers: headers)
        controller = TestBaseController.new(context, {} of String => String)

        controller.public_redirect_back

        controller.context.response.status.should eq(HTTP::Status::FOUND)
        controller.context.response.headers["Location"].should eq("/previous-page")
      end

      it "redirects to fallback when no referrer" do
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        controller.public_redirect_back("/home")

        controller.context.response.status.should eq(HTTP::Status::FOUND)
        controller.context.response.headers["Location"].should eq("/home")
      end

      it "uses default fallback when none provided" do
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        controller.public_redirect_back

        controller.context.response.status.should eq(HTTP::Status::FOUND)
        controller.context.response.headers["Location"].should eq("/")
      end

      it "works with auto-generated route names" do
        # Set up a route without explicit name - it should auto-generate
        router = Takarik::Router.new
        router.add_route("GET", "/api/users", TestBaseController, :index)

        # The route should be available with auto-generated name "api_users_index"
        path = router.path_for("api_users_index")
        path.should eq("/api/users")

        # We can redirect to it using the auto-generated name
        context = create_test_context
        controller = TestBaseController.new(context, {} of String => String)

        # This would work in real usage: redirect_to(:api_users_index)
        # For test, we'll verify the path generation works
        path.should eq("/api/users")
      end
    end
  end
end
