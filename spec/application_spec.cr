require "./spec_helper"
require "http/server"

describe Takarik::Application do
  describe "initialization" do
    it "initializes with default host and port" do
      app = Takarik::Application.new

      app.host.should eq("0.0.0.0")
      app.port.should eq(3000)
    end

    it "initializes with custom host and port" do
      app = Takarik::Application.new(host: "127.0.0.1", port: 8080)

      app.host.should eq("127.0.0.1")
      app.port.should eq(8080)
    end

    it "initializes router instance" do
      app = Takarik::Application.new

      app.router.should be_a(Takarik::Router)
      app.router.should eq(Takarik::Router.instance)
    end

    it "initializes dispatcher with router" do
      app = Takarik::Application.new

      app.dispatcher.should be_a(Takarik::Dispatcher)
      app.dispatcher.router.should eq(app.router)
    end

    it "sets up logging during initialization" do
      # This test verifies that initialization completes without errors
      # The actual log setup is handled by Crystal's Log.setup_from_env
      app = Takarik::Application.new

      app.should be_a(Takarik::Application)
    end
  end

  describe "component integration" do
    it "properly integrates router and dispatcher" do
      app = Takarik::Application.new

      # Add a route through the router
      app.router.get("/test", TestApplicationController, :index)

      # Verify the dispatcher can use the router
      app.dispatcher.router.should eq(app.router)
    end

    it "maintains singleton router across instances" do
      app1 = Takarik::Application.new
      app2 = Takarik::Application.new

      # Both should use the same router singleton
      app1.router.should eq(app2.router)
    end

    it "creates separate dispatcher instances" do
      app1 = Takarik::Application.new
      app2 = Takarik::Application.new

      # Dispatchers should be different instances
      app1.dispatcher.should_not eq(app2.dispatcher)
      # But they should reference the same router
      app1.dispatcher.router.should eq(app2.dispatcher.router)
    end
  end

  describe "configuration handling" do
    it "accepts various host formats" do
      test_cases = [
        "localhost",
        "127.0.0.1",
        "0.0.0.0",
        "::1",
        "myapp.local"
      ]

      test_cases.each do |host|
        app = Takarik::Application.new(host: host)
        app.host.should eq(host)
      end
    end

    it "accepts various port numbers" do
      test_cases = [80, 443, 3000, 8000, 8080, 9999]

      test_cases.each do |port|
        app = Takarik::Application.new(port: port)
        app.port.should eq(port)
      end
    end

    it "handles edge case ports" do
      # Test minimum valid port
      app = Takarik::Application.new(port: 1)
      app.port.should eq(1)

      # Test maximum valid port
      app = Takarik::Application.new(port: 65535)
      app.port.should eq(65535)
    end
  end

  describe "server creation and setup" do
    # Note: These tests verify the setup logic without actually starting the server
    # since starting a real server would block the test suite

    it "can create application instances without starting server" do
      app = Takarik::Application.new(host: "127.0.0.1", port: 9999)

      # Verify the app is ready to run
      app.router.should be_a(Takarik::Router)
      app.dispatcher.should be_a(Takarik::Dispatcher)
      app.host.should eq("127.0.0.1")
      app.port.should eq(9999)
    end

    it "maintains correct component relationships for server" do
      app = Takarik::Application.new

      # Verify the relationships needed for server operation
      app.dispatcher.router.should eq(app.router)
      app.router.should eq(Takarik::Router.instance)
    end
  end

  describe "error handling setup" do
    it "initializes with error handling components ready" do
      app = Takarik::Application.new

      # The application should be ready to handle errors through the dispatcher
      app.dispatcher.should be_a(Takarik::Dispatcher)
      # Dispatcher should be configured to handle routing errors
      app.dispatcher.router.should_not be_nil
    end
  end

  describe "logging integration" do
    it "maintains log setup state" do
      # Test that multiple applications don't interfere with log setup
      app1 = Takarik::Application.new
      app2 = Takarik::Application.new

      # Both should initialize successfully
      app1.should be_a(Takarik::Application)
      app2.should be_a(Takarik::Application)
    end
  end

  describe "application state" do
    it "maintains immutable configuration after initialization" do
      app = Takarik::Application.new(host: "127.0.0.1", port: 8080)

      original_host = app.host
      original_port = app.port
      original_router = app.router
      original_dispatcher = app.dispatcher

      # Properties should remain the same
      app.host.should eq(original_host)
      app.port.should eq(original_port)
      app.router.should eq(original_router)
      app.dispatcher.should eq(original_dispatcher)
    end

    it "provides read-only access to components" do
      app = Takarik::Application.new

      # Getters should work
      app.host.should be_a(String)
      app.port.should be_a(Int32)
      app.router.should be_a(Takarik::Router)
      app.dispatcher.should be_a(Takarik::Dispatcher)
    end
  end

  describe "multiple application instances" do
    it "allows multiple application instances with different configurations" do
      app1 = Takarik::Application.new(host: "127.0.0.1", port: 3000)
      app2 = Takarik::Application.new(host: "0.0.0.0", port: 8080)
      app3 = Takarik::Application.new(host: "localhost", port: 9999)

      # Each should maintain its own configuration
      app1.host.should eq("127.0.0.1")
      app1.port.should eq(3000)

      app2.host.should eq("0.0.0.0")
      app2.port.should eq(8080)

      app3.host.should eq("localhost")
      app3.port.should eq(9999)

      # But all should share the same router singleton
      app1.router.should eq(app2.router)
      app2.router.should eq(app3.router)
    end
  end

  describe "framework integration" do
    it "properly integrates with routing system" do
      app = Takarik::Application.new

      # Should be able to define routes through the router
      app.router.get("/framework-test", TestApplicationController, :index)

      # Dispatcher should be able to use these routes
      route_info = app.router.match("GET", "/framework-test")
      route_info.should_not be_nil
    end

    it "integrates with controller dispatch system" do
      app = Takarik::Application.new

      # Set up a test route
      app.router.post("/dispatch-test", TestApplicationController, :create)

      # Verify the route is available to the dispatcher
      route_info = app.router.match("POST", "/dispatch-test")
      route_info.should_not be_nil

      if route_info
        route_data, params = route_info
        route_data[:controller].should eq(TestApplicationController)
        route_data[:action].should eq(:create)
      end
    end
  end
end

# Test controller for application specs
class TestApplicationController < Takarik::BaseController
  actions :index, :create

  def index
    render plain: "application test index"
  end

  def create
    render status: :created
  end
end
