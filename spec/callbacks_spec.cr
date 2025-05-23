require "./spec_helper"

# Create test controllers for callback specs
class CallbackTestController < Takarik::BaseController
  include Takarik::Callbacks

  actions :index, :show, :create, :update, :destroy, :special_action

  property before_calls : Array(String) = [] of String
  property after_calls : Array(String) = [] of String
  property action_calls : Array(String) = [] of String

  before_actions([
    {method: :log_request, only: nil, except: nil},
    {method: :authenticate, only: [:show, :create, :update, :destroy], except: nil},
    {method: :authorize_admin, only: [:destroy], except: nil}
  ])

  after_actions([
    {method: :log_response, only: nil, except: nil},
    {method: :cleanup_session, only: [:destroy], except: nil}
  ])

  def index
    @action_calls << "index"
    render plain: "index"
  end

  def show
    @action_calls << "show"
    render plain: "show"
  end

  def create
    @action_calls << "create"
    render status: :created
  end

  def update
    @action_calls << "update"
    render plain: "update"
  end

  def destroy
    @action_calls << "destroy"
    render status: :no_content
  end

  def special_action
    @action_calls << "special_action"
    render plain: "special"
  end

  private def log_request
    @before_calls << "log_request"
    true
  end

  private def authenticate
    @before_calls << "authenticate"
    true
  end

  private def authorize_admin
    @before_calls << "authorize_admin"
    true
  end

  private def log_response
    @after_calls << "log_response"
  end

  private def cleanup_session
    @after_calls << "cleanup_session"
  end
end

class HaltingCallbackController < Takarik::BaseController
  include Takarik::Callbacks

  actions :open_action, :protected_action, :admin_action

  property before_calls : Array(String) = [] of String
  property after_calls : Array(String) = [] of String
  property action_calls : Array(String) = [] of String

  before_actions([
    {method: :always_run, only: nil, except: nil},
    {method: :check_auth, only: [:protected_action, :admin_action], except: nil},
    {method: :check_admin, only: [:admin_action], except: nil}
  ])

  after_actions([
    {method: :always_cleanup, only: nil, except: nil}
  ])

  def open_action
    @action_calls << "open_action"
    render plain: "open"
  end

  def protected_action
    @action_calls << "protected_action"
    render plain: "protected"
  end

  def admin_action
    @action_calls << "admin_action"
    render plain: "admin"
  end

  private def always_run
    @before_calls << "always_run"
    true
  end

  private def check_auth
    @before_calls << "check_auth"
    false # This will halt processing
  end

  private def check_admin
    @before_calls << "check_admin"
    true
  end

  private def always_cleanup
    @after_calls << "always_cleanup"
  end
end

class ExceptFilterController < Takarik::BaseController
  include Takarik::Callbacks

  actions :public_action, :private_action, :special_action

  property before_calls : Array(String) = [] of String
  property after_calls : Array(String) = [] of String

  before_actions([
    {method: :check_maintenance, only: nil, except: [:public_action]}
  ])

  after_actions([
    {method: :track_usage, only: nil, except: [:special_action]}
  ])

  def public_action
    render plain: "public"
  end

  def private_action
    render plain: "private"
  end

  def special_action
    render plain: "special"
  end

  private def check_maintenance
    @before_calls << "check_maintenance"
    true
  end

  private def track_usage
    @after_calls << "track_usage"
  end
end

class MultipleCallbackController < Takarik::BaseController
  include Takarik::Callbacks

  actions :test_action

  property callback_order : Array(String) = [] of String

  before_actions([
    {method: :first_before, only: nil, except: nil},
    {method: :second_before, only: nil, except: nil},
    {method: :third_before, only: nil, except: nil}
  ])

  after_actions([
    {method: :first_after, only: nil, except: nil},
    {method: :second_after, only: nil, except: nil},
    {method: :third_after, only: nil, except: nil}
  ])

  def test_action
    @callback_order << "action"
    render plain: "test"
  end

  private def first_before
    @callback_order << "first_before"
    true
  end

  private def second_before
    @callback_order << "second_before"
    true
  end

  private def third_before
    @callback_order << "third_before"
    true
  end

  private def first_after
    @callback_order << "first_after"
  end

  private def second_after
    @callback_order << "second_after"
  end

  private def third_after
    @callback_order << "third_after"
  end
end

class NoCallbackController < Takarik::BaseController
  actions :simple_action

  def simple_action
    render plain: "simple"
  end
end

describe Takarik::Callbacks do
  describe "before_actions macro" do
    it "generates run_before_action method" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      controller.responds_to?(:run_before_action).should be_true
    end

    it "executes callbacks for matching actions" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:show)

      result.should be_true
      controller.before_calls.should contain("log_request")
      controller.before_calls.should contain("authenticate")
      controller.before_calls.should_not contain("authorize_admin")
    end

    it "executes all callbacks for actions without filters" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:destroy)

      result.should be_true
      controller.before_calls.should eq(["log_request", "authenticate", "authorize_admin"])
    end

    it "skips callbacks based on only filter" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:index)

      result.should be_true
      controller.before_calls.should eq(["log_request"])
    end

    it "returns false when any callback returns false but executes all callbacks" do
      controller = HaltingCallbackController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:protected_action)

      result.should be_false
      controller.before_calls.should eq(["always_run", "check_auth"])
    end

    it "executes all callbacks even when one returns false" do
      controller = HaltingCallbackController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:admin_action)

      result.should be_false
      # All callbacks execute, but result is false because check_auth returns false
      controller.before_calls.should eq(["always_run", "check_auth", "check_admin"])
    end

    it "works with except filters" do
      controller = ExceptFilterController.new(create_test_context, {} of String => String)

      # Should not run for public_action (in except list)
      result = controller.run_before_action(:public_action)
      result.should be_true
      controller.before_calls.should be_empty

      # Should run for private_action (not in except list)
      controller.before_calls.clear
      result = controller.run_before_action(:private_action)
      result.should be_true
      controller.before_calls.should eq(["check_maintenance"])
    end
  end

  describe "after_actions macro" do
    it "generates run_after_action method" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      controller.responds_to?(:run_after_action).should be_true
    end

    it "executes callbacks for matching actions" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_after_action(:destroy)

      result.should be_true
      controller.after_calls.should eq(["log_response", "cleanup_session"])
    end

    it "executes only global callbacks for non-matching actions" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_after_action(:index)

      result.should be_true
      controller.after_calls.should eq(["log_response"])
    end

    it "always returns true" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_after_action(:any_action)

      result.should be_true
    end

    it "works with except filters" do
      controller = ExceptFilterController.new(create_test_context, {} of String => String)

      # Should not run for special_action (in except list)
      result = controller.run_after_action(:special_action)
      result.should be_true
      controller.after_calls.should be_empty

      # Should run for other actions
      controller.after_calls.clear
      result = controller.run_after_action(:private_action)
      result.should be_true
      controller.after_calls.should eq(["track_usage"])
    end
  end

  describe "callback execution order" do
    it "executes before callbacks in definition order" do
      controller = MultipleCallbackController.new(create_test_context, {} of String => String)

      controller.run_before_action(:test_action)

      before_callbacks = controller.callback_order.select { |call| call.includes?("before") }
      before_callbacks.should eq(["first_before", "second_before", "third_before"])
    end

    it "executes after callbacks in definition order" do
      controller = MultipleCallbackController.new(create_test_context, {} of String => String)

      controller.run_after_action(:test_action)

      after_callbacks = controller.callback_order.select { |call| call.includes?("after") }
      after_callbacks.should eq(["first_after", "second_after", "third_after"])
    end
  end

  describe "conditional callback execution" do
    it "handles multiple actions in only filter" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      # Test multiple actions that should trigger authenticate
      [:show, :create, :update, :destroy].each do |action|
        controller.before_calls.clear
        controller.run_before_action(action)
        controller.before_calls.should contain("authenticate")
      end
    end

    it "handles actions not in only filter" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      controller.run_before_action(:index)
      controller.before_calls.should_not contain("authenticate")

      controller.before_calls.clear
      controller.run_before_action(:special_action)
      controller.before_calls.should_not contain("authenticate")
    end

    it "handles empty callback arrays gracefully" do
      # Test with a controller that has no callbacks
      controller = NoCallbackController.new(create_test_context, {} of String => String)

      # Should not have callback methods if no callbacks defined
      controller.responds_to?(:run_before_action).should be_false
      controller.responds_to?(:run_after_action).should be_false
    end
  end

  describe "callback filtering edge cases" do
    it "handles nil only and except filters" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      # log_request has nil for both only and except, so should run for any action
      controller.run_before_action(:any_random_action)
      controller.before_calls.should contain("log_request")
    end

    it "handles single symbol in only filter" do
      # Test that our array-based filtering works correctly
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      controller.run_before_action(:destroy)
      controller.before_calls.should contain("authorize_admin")

      controller.before_calls.clear
      controller.run_before_action(:show)
      controller.before_calls.should_not contain("authorize_admin")
    end
  end

  describe "integration with controllers" do
    it "maintains callback state independently per controller instance" do
      controller1 = CallbackTestController.new(create_test_context, {} of String => String)
      controller2 = CallbackTestController.new(create_test_context, {} of String => String)

      controller1.run_before_action(:show)
      controller2.run_before_action(:index)

      controller1.before_calls.should contain("authenticate")
      controller2.before_calls.should_not contain("authenticate")
    end

    it "works with inheritance" do
      # The callback macros should work with inherited controllers
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      # Should have inherited BaseController functionality
      controller.should be_a(Takarik::BaseController)

      # Should have callback functionality
      controller.responds_to?(:run_before_action).should be_true
      controller.responds_to?(:run_after_action).should be_true
    end
  end

  describe "callback return value handling" do
    it "treats all truthy returns as continue" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:show)

      # All callbacks return true, so overall should be true
      result.should be_true
    end

    it "treats any false return as halt" do
      controller = HaltingCallbackController.new(create_test_context, {} of String => String)

      result = controller.run_before_action(:protected_action)

      # check_auth returns false, so overall should be false
      result.should be_false
    end

    it "chains boolean results correctly" do
      # This tests the result = result && callback_result logic
      controller = HaltingCallbackController.new(create_test_context, {} of String => String)

      # For open_action, all callbacks return true
      result = controller.run_before_action(:open_action)
      result.should be_true

      # For protected actions, one callback returns false
      controller.before_calls.clear
      result = controller.run_before_action(:protected_action)
      result.should be_false
    end
  end

  describe "macro-generated code" do
    it "generates methods that accept action symbols" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      # Should accept any symbol
      controller.run_before_action(:test).should be_true
      controller.run_after_action(:test).should be_true
    end

    it "handles action filtering correctly" do
      controller = CallbackTestController.new(create_test_context, {} of String => String)

      # Test that the macro-generated filtering logic works
      test_cases = [
        {:index, ["log_request"]},
        {:show, ["log_request", "authenticate"]},
        {:destroy, ["log_request", "authenticate", "authorize_admin"]}
      ]

      test_cases.each do |action, expected_calls|
        controller.before_calls.clear
        controller.run_before_action(action)
        controller.before_calls.should eq(expected_calls)
      end
    end
  end
end

# Helper method for creating test contexts
def create_test_context
  request = HTTP::Request.new("GET", "/")
  response_io = IO::Memory.new
  response = HTTP::Server::Response.new(response_io)
  HTTP::Server::Context.new(request, response)
end
