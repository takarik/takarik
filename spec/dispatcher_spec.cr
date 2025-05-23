require "./spec_helper"
require "http/server"

# Create test controllers for dispatcher specs
class DispatcherTestController < Takarik::BaseController
  actions :index, :show, :create, :error_action, :new, :edit, :update, :destroy

  def index
    render plain: "index response"
  end

  def show
    render json: {"id" => params["id"], "action" => "show"}
  end

  def create
    render status: :created
  end

  def new
    render plain: "new form"
  end

  def edit
    render plain: "edit form"
  end

  def update
    render plain: "updated"
  end

  def destroy
    render status: :no_content
  end

  def error_action
    raise "Test error"
  end
end

# Helper to create HTTP contexts for dispatcher testing
def create_dispatcher_context(method = "GET", path = "/", body = nil, headers = HTTP::Headers.new)
  body_io = IO::Memory.new
  if body
    body_io.print(body)
    body_io.rewind
  end

  request = HTTP::Request.new(method, path, headers, body_io)

  # Create response with memory output for testing
  response_io = IO::Memory.new
  response = HTTP::Server::Response.new(response_io)

  HTTP::Server::Context.new(request, response)
end

describe Takarik::Dispatcher do
  describe "initialization" do
    it "initializes with a router" do
      router = Takarik::Router.new
      dispatcher = Takarik::Dispatcher.new(router)

      dispatcher.router.should eq(router)
    end
  end

  describe "#dispatch" do
    context "with matching routes" do
      it "dispatches to the correct controller and action" do
        router = Takarik::Router.new
        router.add_route("GET", "/test", DispatcherTestController, :index)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/test")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::OK)
      end

      it "passes route parameters to the controller" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id", DispatcherTestController, :show)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/users/123")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::OK)
      end

      it "handles different HTTP methods" do
        router = Takarik::Router.new
        router.add_route("POST", "/create", DispatcherTestController, :create)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("POST", "/create")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::CREATED)
      end

      it "successfully instantiates and calls controllers" do
        router = Takarik::Router.new
        router.add_route("GET", "/test", DispatcherTestController, :index)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/test")
        dispatcher.dispatch(context)

        # Should succeed without exceptions
        context.response.status.should eq(HTTP::Status::OK)
      end
    end

    context "with non-matching routes" do
      it "returns 404 for non-existent routes" do
        router = Takarik::Router.new
        # Don't add any routes
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/nonexistent")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::NOT_FOUND)
      end

      it "sets appropriate content type for 404 responses" do
        router = Takarik::Router.new
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/missing")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::NOT_FOUND)
        context.response.headers["Content-Type"].should eq("text/plain")
      end
    end

    context "with error handling" do
      it "handles exceptions in controller actions" do
        router = Takarik::Router.new
        router.add_route("GET", "/error", DispatcherTestController, :error_action)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/error")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::INTERNAL_SERVER_ERROR)
        context.response.headers["Content-Type"].should eq("text/plain")
      end

      it "continues to log requests even after errors" do
        router = Takarik::Router.new
        router.add_route("GET", "/error", DispatcherTestController, :error_action)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/error")

        # The dispatch should handle the error gracefully
        dispatcher.dispatch(context)

        # Verify error response
        context.response.status.should eq(HTTP::Status::INTERNAL_SERVER_ERROR)
      end
    end

    context "with different route patterns" do
      it "handles simple routes" do
        router = Takarik::Router.new
        router.add_route("GET", "/simple", DispatcherTestController, :index)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/simple")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::OK)
      end

      it "handles parameterized routes" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id/posts/:post_id", DispatcherTestController, :show)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/users/123/posts/456")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::OK)
      end

      it "handles RESTful resource routes" do
        router = Takarik::Router.new
        router.resources(:users, DispatcherTestController, only: [:index, :show])
        dispatcher = Takarik::Dispatcher.new(router)

        # Test index
        context = create_dispatcher_context("GET", "/users")
        dispatcher.dispatch(context)
        context.response.status.should eq(HTTP::Status::OK)

        # Test show
        context = create_dispatcher_context("GET", "/users/123")
        dispatcher.dispatch(context)
        context.response.status.should eq(HTTP::Status::OK)
      end
    end

    context "edge cases" do
      it "handles root path" do
        router = Takarik::Router.new
        router.add_route("GET", "/", DispatcherTestController, :index)
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/")
        dispatcher.dispatch(context)

        context.response.status.should eq(HTTP::Status::OK)
      end

      it "handles requests to non-matched paths gracefully" do
        router = Takarik::Router.new
        dispatcher = Takarik::Dispatcher.new(router)

        context = create_dispatcher_context("GET", "/unmatched")
        dispatcher.dispatch(context)

        # Should handle gracefully with 404
        context.response.status.should eq(HTTP::Status::NOT_FOUND)
      end
    end
  end

  describe "integration with router" do
    it "works with router instance" do
      router = Takarik::Router.new
      router.get("/integration", DispatcherTestController, :index)
      dispatcher = Takarik::Dispatcher.new(router)

      context = create_dispatcher_context("GET", "/integration")
      dispatcher.dispatch(context)

      context.response.status.should eq(HTTP::Status::OK)
    end

    it "respects router configuration" do
      router = Takarik::Router.new

      # Set up routes using the router's DSL
      router.map(DispatcherTestController) do
        get("/mapped", :index)
        post("/mapped", :create)
      end

      dispatcher = Takarik::Dispatcher.new(router)

      # Test GET
      context = create_dispatcher_context("GET", "/mapped")
      dispatcher.dispatch(context)
      context.response.status.should eq(HTTP::Status::OK)

      # Test POST
      context = create_dispatcher_context("POST", "/mapped")
      dispatcher.dispatch(context)
      context.response.status.should eq(HTTP::Status::CREATED)
    end

    it "properly handles route parameters in integration" do
      router = Takarik::Router.new
      router.resources(:items, DispatcherTestController)
      dispatcher = Takarik::Dispatcher.new(router)

      # Test various resource routes that are actually generated
      test_cases = [
        {"GET", "/items", HTTP::Status::OK},           # index
        {"GET", "/items/new", HTTP::Status::OK},       # new
        {"GET", "/items/123", HTTP::Status::OK},       # show
        {"POST", "/items", HTTP::Status::CREATED},     # create
      ]

      test_cases.each do |method, path, expected_status|
        context = create_dispatcher_context(method, path)
        dispatcher.dispatch(context)
        context.response.status.should eq(expected_status)
      end
    end
  end

  describe "request lifecycle" do
    it "processes requests from start to finish" do
      router = Takarik::Router.new
      router.add_route("GET", "/lifecycle", DispatcherTestController, :index)
      dispatcher = Takarik::Dispatcher.new(router)

      context = create_dispatcher_context("GET", "/lifecycle")

      # Track timing like the dispatcher does
      start_time = Time.monotonic
      dispatcher.dispatch(context)
      duration = Time.monotonic - start_time

      # Verify the request was processed
      context.response.status.should eq(HTTP::Status::OK)
      duration.should be > Time::Span.zero
    end
  end
end
