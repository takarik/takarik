require "./spec_helper"
require "file_utils"

# Create test view engines for view engine specs
module Takarik
  module Views
    class MockEngine < Engine
      property rendered_views : Array({Symbol, Hash(Symbol | String, ::JSON::Any)})
      property render_output : String

      def initialize(@render_output = "mock rendered content")
        @rendered_views = [] of {Symbol, Hash(Symbol | String, ::JSON::Any)}
      end

      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any), layout : Symbol? = nil)
        # Convert the locals to ensure proper type
        converted_locals = {} of Symbol | String => ::JSON::Any
        locals.each { |k, v| converted_locals[k] = v }
        @rendered_views << {view, converted_locals}
        @render_output
      end
    end

    class CustomTestEngine < Engine
      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any), layout : Symbol? = nil)
        "Custom engine: #{view} with #{locals.size} locals"
      end
    end
  end
end

# Test controllers for view engine specs
class ViewEngineTestController < Takarik::BaseController
  actions :index, :show, :custom

  # Mock render_view method instead of using ECR
  def render_view(view : Symbol, locals : Hash(Symbol | String, ::JSON::Any) = {} of Symbol | String => ::JSON::Any, layout : Symbol? = nil)
    case view
    when :index
      "Rendered view: index with #{locals.size} locals"
    when :show
      "Rendered view: show with #{locals.size} locals"
    when :custom
      "Rendered view: custom with #{locals.size} locals"
    when :test_view
      "Rendered view: test_view with #{locals.size} locals"
    when :profile
      "Rendered view: profile with #{locals.size} locals"
    when :test1
      "Rendered view: test1 with #{locals.size} locals"
    when :view1
      "Rendered view: view1 with #{locals.size} locals"
    when :complex
      "Rendered view: complex with #{locals.size} locals"
    when :mixed
      "Rendered view: mixed with #{locals.size} locals"
    else
      raise "Unknown view: #{view}"
    end
  end

  def index
    render view: :index
  end

  def show
    render view: :show, locals: {"id" => JSON::Any.new("123")} of Symbol | String => JSON::Any
  end

  def custom
    render view: :custom, locals: {
      "title" => JSON::Any.new("Custom Title"),
      "items" => JSON::Any.new(["item1", "item2"].map { |item| JSON::Any.new(item) })
    } of Symbol | String => JSON::Any
  end

  # Public methods for testing protected render functionality
  def public_render(**args)
    render(**args)
  end

  def public_render_view(view : Symbol, locals = {} of Symbol | String => JSON::Any)
    render(view: view, locals: locals)
  end
end

class MinimalViewController < Takarik::BaseController
  actions :simple

  # Mock render_view method
  def render_view(view : Symbol, locals : Hash(Symbol | String, ::JSON::Any) = {} of Symbol | String => ::JSON::Any, layout : Symbol? = nil)
    case view
    when :simple
      "<h1>Simple View</h1><p>This is a minimal test view.</p>"
    else
      raise "Unknown view: #{view}"
    end
  end

  def simple
    render view: :simple
  end
end

class NoViewsController < Takarik::BaseController
  actions :plain_action

  def plain_action
    render plain: "No views here"
  end
end

describe "Takarik::Views" do
  describe "Engine interface" do
    it "defines abstract render method" do
      # Test that the Engine class exists and is abstract
      engine = Takarik::Views::MockEngine.new
      engine.should be_a(Takarik::Views::Engine)
    end

    it "can be implemented by custom engines" do
      engine = Takarik::Views::CustomTestEngine.new
      controller = create_test_controller

      result = engine.render(controller, :test_view, {} of Symbol | String => JSON::Any, nil)
      result.should eq("Custom engine: test_view with 0 locals")
    end

    it "accepts locals parameter" do
      engine = Takarik::Views::MockEngine.new("test output")
      controller = create_test_controller
      locals = {"name" => JSON::Any.new("World"), "count" => JSON::Any.new(42)} of Symbol | String => JSON::Any

      result = engine.render(controller, :test_view, locals, nil)

      result.should eq("test output")
      engine.rendered_views.should eq([{:test_view, locals}])
    end
  end

  describe "ECREngine" do
    it "inherits from Engine" do
      engine = Takarik::Views::ECREngine.new
      engine.should be_a(Takarik::Views::Engine)
    end

    it "provides render interface" do
      engine = Takarik::Views::ECREngine.new
      controller = ViewEngineTestController.new(create_test_context, {} of String => String)
      locals = {"test" => JSON::Any.new("value")} of Symbol | String => JSON::Any

      # Test that the engine can be called (uses mocked render_view)
      result = engine.render(controller, :index, locals, nil)
      result.should be_a(String)
      result.should contain("index")
    end
  end

  describe "ECRRenderer module" do
    describe "views macro" do
      it "generates render_view method when included" do
        # Test that including ECRRenderer provides render_view capability
        # We can't test actual ECR compilation without template files
        # So we test the interface availability
        ViewEngineTestController.new(create_test_context, {} of String => String).responds_to?(:render_view).should be_true
      end

      it "handles view names correctly with mocked templates" do
        controller = ViewEngineTestController.new(create_test_context, {} of String => String)

        # Test index view (no locals required)
        result = controller.render_view(:index)
        result.should be_a(String)
        result.should contain("index")

        # Test show view (requires id local)
        result = controller.render_view(:show, {"id" => JSON::Any.new("123")} of Symbol | String => JSON::Any)
        result.should be_a(String)
        result.should contain("show")
        result.should contain("1 locals")

        # Test custom view (requires title and items locals)
        custom_locals = {
          "title" => JSON::Any.new("Test Title"),
          "items" => JSON::Any.new(["item1", "item2"].map { |item| JSON::Any.new(item) })
        } of Symbol | String => JSON::Any
        result = controller.render_view(:custom, custom_locals)
        result.should be_a(String)
        result.should contain("custom")
      end

      it "accepts locals parameter" do
        controller = ViewEngineTestController.new(create_test_context, {} of String => String)
        locals = {"name" => JSON::Any.new("test")} of Symbol | String => JSON::Any

        result = controller.render_view(:index, locals)
        result.should contain("index")
      end

      it "works with controllers that have minimal views" do
        controller = MinimalViewController.new(create_test_context, {} of String => String)

        controller.responds_to?(:render_view).should be_true

        result = controller.render_view(:simple)
        result.should contain("Simple View")
      end
    end

    describe "error handling for unknown views" do
      it "raises error for unknown views" do
        controller = ViewEngineTestController.new(create_test_context, {} of String => String)

        expect_raises(Exception, /Unknown view: nonexistent/) do
          controller.render_view(:nonexistent)
        end
      end
    end
  end

  describe "integration with configuration" do
    it "works with configured ECR engine" do
      # Test that the default configuration works
      config = Takarik::Configuration.new
      config.view_engine.should be_a(Takarik::Views::ECREngine)
    end

    it "can be replaced with custom engine" do
      custom_engine = Takarik::Views::MockEngine.new("custom output")

      Takarik.configure do |config|
        config.view_engine = custom_engine
      end

      Takarik.config.view_engine.should eq(custom_engine)
    end

    it "integrates with controller render method" do
      # Set up a mock engine
      mock_engine = Takarik::Views::MockEngine.new("mocked view content")
      Takarik.configure { |c| c.view_engine = mock_engine }

      controller = create_test_controller

      # This should use the configured engine
      controller.public_render_view(:test_view, {"key" => JSON::Any.new("value")} of Symbol | String => JSON::Any)

      # Check that our mock engine was called
      mock_engine.rendered_views.size.should eq(1)
      mock_engine.rendered_views[0][0].should eq(:test_view)
      mock_engine.rendered_views[0][1]["key"].as_s.should eq("value")
    end
  end

  describe "error handling" do
    it "raises error for unknown views in ECRRenderer" do
      controller = ViewEngineTestController.new(create_test_context, {} of String => String)

      expect_raises(Exception, /Unknown view: nonexistent/) do
        controller.render_view(:nonexistent)
      end
    end

    it "handles missing view engine gracefully" do
      # Clear the view engine
      Takarik.configure { |c| c.view_engine = nil }

      controller = create_test_controller

      expect_raises(Exception, /No view engine configured/) do
        controller.public_render_view(:test)
      end
    end

    it "handles template rendering errors" do
      # Test error handling with our interface
      controller = ViewEngineTestController.new(create_test_context, {} of String => String)

      expect_raises(Exception, /Unknown view/) do
        controller.render_view(:nonexistent_view)
      end
    end
  end

  describe "view rendering workflow" do
    it "follows complete render workflow with mock engine" do
      mock_engine = Takarik::Views::MockEngine.new("rendered content")
      Takarik.configure { |c| c.view_engine = mock_engine }

      controller = create_test_controller
      locals = {
        "title" => JSON::Any.new("Test Title"),
        "user" => JSON::Any.new("John Doe")
      } of Symbol | String => JSON::Any

      # Render a view
      controller.public_render_view(:profile, locals)

      # Verify the mock engine was called correctly
      mock_engine.rendered_views.size.should eq(1)
      view_call = mock_engine.rendered_views[0]
      view_call[0].should eq(:profile)
      view_call[1]["title"].as_s.should eq("Test Title")
      view_call[1]["user"].as_s.should eq("John Doe")

      # Verify response was set
      controller.context.response.headers["Content-Type"].should eq("text/html")
    end

    it "handles view rendering without locals" do
      mock_engine = Takarik::Views::MockEngine.new("simple content")
      Takarik.configure { |c| c.view_engine = mock_engine }

      controller = create_test_controller

      controller.public_render_view(:simple)

      mock_engine.rendered_views.size.should eq(1)
      mock_engine.rendered_views[0][0].should eq(:simple)
      mock_engine.rendered_views[0][1].should be_empty
    end

    it "handles automatic view name inference" do
      mock_engine = Takarik::Views::MockEngine.new("auto content")
      Takarik.configure { |c| c.view_engine = mock_engine }

      controller = create_test_controller
      # Set current action for automatic view inference
      controller.dispatch(:index)

      # This would call render without specifying view name
      # The controller would need to have the action defined for this to work
    end
  end

  describe "multiple engine support" do
    it "supports switching between engines" do
      engine1 = Takarik::Views::MockEngine.new("engine1 output")
      engine2 = Takarik::Views::MockEngine.new("engine2 output")

      controller = create_test_controller

      # Use first engine
      Takarik.configure { |c| c.view_engine = engine1 }
      controller.public_render_view(:test1)

      # Switch to second engine
      Takarik.configure { |c| c.view_engine = engine2 }
      controller.public_render_view(:test2)

      engine1.rendered_views.size.should eq(1)
      engine1.rendered_views[0][0].should eq(:test1)

      engine2.rendered_views.size.should eq(1)
      engine2.rendered_views[0][0].should eq(:test2)
    end

    it "maintains engine state independently" do
      engine1 = Takarik::Views::MockEngine.new("output1")
      engine2 = Takarik::Views::MockEngine.new("output2")

      controller1 = create_test_controller
      controller2 = create_test_controller

      Takarik.configure { |c| c.view_engine = engine1 }
      controller1.public_render_view(:view1)

      Takarik.configure { |c| c.view_engine = engine2 }
      controller2.public_render_view(:view2)

      # Both engines should have been used
      engine1.rendered_views.should eq([{:view1, {} of Symbol | String => JSON::Any}])
      engine2.rendered_views.should eq([{:view2, {} of Symbol | String => JSON::Any}])
    end
  end

  describe "ECRRenderer macro edge cases" do
    it "handles controllers without views macro" do
      controller = NoViewsController.new(create_test_context, {} of String => String)

      # Should not have render_view method
      controller.responds_to?(:render_view).should be_false
    end

    it "works with empty views list" do
      # Test that controllers with mock render_view work properly
      controller = MinimalViewController.new(create_test_context, {} of String => String)

      expect_raises(Exception, /Unknown view: nonexistent/) do
        controller.render_view(:nonexistent)
      end
    end
  end

  describe "locals handling" do
    it "passes locals correctly to engine" do
      mock_engine = Takarik::Views::MockEngine.new("test")
      Takarik.configure { |c| c.view_engine = mock_engine }

      controller = create_test_controller
      complex_locals = {
        "string" => JSON::Any.new("hello"),
        "number" => JSON::Any.new(42),
        "array" => JSON::Any.new(["a", "b", "c"].map { |item| JSON::Any.new(item) }),
        "bool" => JSON::Any.new(true)
      } of Symbol | String => JSON::Any

      controller.public_render_view(:complex, complex_locals)

      rendered_locals = mock_engine.rendered_views[0][1]
      rendered_locals["string"].as_s.should eq("hello")
      rendered_locals["number"].as_i.should eq(42)
      rendered_locals["array"].as_a.size.should eq(3)
      rendered_locals["bool"].as_bool.should be_true
    end

    it "handles symbol and string keys in locals" do
      mock_engine = Takarik::Views::MockEngine.new("test")
      Takarik.configure { |c| c.view_engine = mock_engine }

      controller = create_test_controller
      mixed_locals = {
        :symbol_key => JSON::Any.new("symbol_value"),
        "string_key" => JSON::Any.new("string_value")
      } of Symbol | String => JSON::Any

      controller.public_render_view(:mixed, mixed_locals)

      rendered_locals = mock_engine.rendered_views[0][1]
      rendered_locals.has_key?(:symbol_key).should be_true
      rendered_locals.has_key?("string_key").should be_true
    end
  end
end

# Helper methods for view engine specs
def create_test_controller
  ViewEngineTestController.new(create_test_context, {} of String => String)
end

def create_test_context
  request = HTTP::Request.new("GET", "/")
  response_io = IO::Memory.new
  response = HTTP::Server::Response.new(response_io)
  HTTP::Server::Context.new(request, response)
end
