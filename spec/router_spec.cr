require "./spec_helper"

# Create test controllers for specs
class TestController < Takarik::BaseController
  actions :index, :show, :create, :update, :destroy, :new, :edit, :custom

  def index
    render plain: "index"
  end

  def show
    render plain: "show"
  end

  def create
    render plain: "create"
  end

  def update
    render plain: "update"
  end

  def destroy
    render plain: "destroy"
  end

  def new
    render plain: "new"
  end

  def edit
    render plain: "edit"
  end

  def custom
    render plain: "custom"
  end
end

class UsersController < Takarik::BaseController
  actions :index, :show, :create, :update, :destroy, :new, :edit

  def index
    render plain: "users index"
  end

  def show
    render plain: "users show"
  end

  def create
    render plain: "users create"
  end

  def update
    render plain: "users update"
  end

  def destroy
    render plain: "users destroy"
  end

  def new
    render plain: "users new"
  end

  def edit
    render plain: "users edit"
  end
end

describe Takarik::Router do
  describe "#add_route" do
    it "adds a simple route" do
      router = Takarik::Router.new
      router.add_route("GET", "/test", TestController, :index)

      result = router.match("GET", "/test")
      result.should_not be_nil

      if result
        route_info, params = result
        route_info[:http_method].should eq("GET")
        route_info[:controller].should eq(TestController)
        route_info[:action].should eq(:index)
        params.should be_empty
      end
    end

    it "adds routes with parameters" do
      router = Takarik::Router.new
      router.add_route("GET", "/users/:id", TestController, :show)

      result = router.match("GET", "/users/123")
      result.should_not be_nil

      if result
        route_info, params = result
        route_info[:http_method].should eq("GET")
        route_info[:controller].should eq(TestController)
        route_info[:action].should eq(:show)
        params["id"].should eq("123")
      end
    end

    it "handles multiple HTTP methods on the same path" do
      router = Takarik::Router.new
      router.add_route("GET", "/test", TestController, :show)
      router.add_route("POST", "/test", TestController, :create)

      get_result = router.match("GET", "/test")
      post_result = router.match("POST", "/test")

      get_result.should_not be_nil
      post_result.should_not be_nil

      if get_result && post_result
        get_route_info, _ = get_result
        post_route_info, _ = post_result

        get_route_info[:action].should eq(:show)
        post_route_info[:action].should eq(:create)
      end
    end
  end

  describe "HTTP verb methods" do
    describe "#get" do
      it "adds a GET route with controller and action" do
        router = Takarik::Router.new
        router.get("/test", TestController, :index)

        result = router.match("GET", "/test")
        result.should_not be_nil

        if result
          route_info, _ = result
          route_info[:http_method].should eq("GET")
          route_info[:controller].should eq(TestController)
          route_info[:action].should eq(:index)
        end
      end
    end

    describe "#post" do
      it "adds a POST route with controller and action" do
        router = Takarik::Router.new
        router.post("/test", TestController, :index)

        result = router.match("POST", "/test")
        result.should_not be_nil

        if result
          route_info, _ = result
          route_info[:http_method].should eq("POST")
          route_info[:controller].should eq(TestController)
          route_info[:action].should eq(:index)
        end
      end
    end

    describe "#put" do
      it "adds a PUT route with controller and action" do
        router = Takarik::Router.new
        router.put("/test", TestController, :index)

        result = router.match("PUT", "/test")
        result.should_not be_nil

        if result
          route_info, _ = result
          route_info[:http_method].should eq("PUT")
          route_info[:controller].should eq(TestController)
          route_info[:action].should eq(:index)
        end
      end
    end

    describe "#patch" do
      it "adds a PATCH route with controller and action" do
        router = Takarik::Router.new
        router.patch("/test", TestController, :index)

        result = router.match("PATCH", "/test")
        result.should_not be_nil

        if result
          route_info, _ = result
          route_info[:http_method].should eq("PATCH")
          route_info[:controller].should eq(TestController)
          route_info[:action].should eq(:index)
        end
      end
    end

    describe "#delete" do
      it "adds a DELETE route with controller and action" do
        router = Takarik::Router.new
        router.delete("/test", TestController, :index)

        result = router.match("DELETE", "/test")
        result.should_not be_nil

        if result
          route_info, _ = result
          route_info[:http_method].should eq("DELETE")
          route_info[:controller].should eq(TestController)
          route_info[:action].should eq(:index)
        end
      end
    end
  end

  describe "#match" do
    it "returns nil for non-existent routes" do
      router = Takarik::Router.new
      result = router.match("GET", "/nonexistent")
      result.should be_nil
    end

    it "returns nil for wrong HTTP method" do
      router = Takarik::Router.new
      router.add_route("GET", "/test", TestController, :index)

      result = router.match("POST", "/test")
      result.should be_nil
    end

    it "extracts multiple route parameters" do
      router = Takarik::Router.new
      router.add_route("GET", "/users/:user_id/posts/:post_id", TestController, :show)

      result = router.match("GET", "/users/123/posts/456")
      result.should_not be_nil

      if result
        route_info, params = result
        params["user_id"].should eq("123")
        params["post_id"].should eq("456")
      end
    end
  end

  describe "#map" do
    it "sets current controller for the block" do
      router = Takarik::Router.new
      router.map(TestController) do
        get("/test", :index)
      end

      result = router.match("GET", "/test")
      result.should_not be_nil

      if result
        route_info, _ = result
        route_info[:controller].should eq(TestController)
        route_info[:action].should eq(:index)
      end
    end

    it "resets current controller after the block" do
      router = Takarik::Router.new
      router.map(TestController) do
        get("/test", :index)
      end

      # This should raise an error since we're outside the controller scope
      expect_raises(Exception, "Controller scope required") do
        router.get("/test2", :show)
      end
    end
  end

  describe "#resources" do
    context "with controller parameter" do
      it "creates all RESTful routes" do
        router = Takarik::Router.new
        router.resources(:users, UsersController)

        # Index
        result = router.match("GET", "/users")
        result.should_not be_nil
        result.not_nil![0][:action].should eq(:index) if result

        # Show
        result = router.match("GET", "/users/123")
        result.should_not be_nil
        if result
          route_info, params = result
          route_info[:action].should eq(:show)
          params["id"].should eq("123")
        end

        # New
        result = router.match("GET", "/users/new")
        result.should_not be_nil
        result.not_nil![0][:action].should eq(:new) if result

        # Create
        result = router.match("POST", "/users")
        result.should_not be_nil
        result.not_nil![0][:action].should eq(:create) if result

        # Edit
        result = router.match("GET", "/users/123/edit")
        result.should_not be_nil
        if result
          route_info, params = result
          route_info[:action].should eq(:edit)
          params["id"].should eq("123")
        end

        # Update (PUT)
        result = router.match("PUT", "/users/123")
        result.should_not be_nil
        if result
          route_info, params = result
          route_info[:action].should eq(:update)
          params["id"].should eq("123")
        end

        # Update (PATCH)
        result = router.match("PATCH", "/users/123")
        result.should_not be_nil
        if result
          route_info, params = result
          route_info[:action].should eq(:update)
          params["id"].should eq("123")
        end

        # Destroy
        result = router.match("DELETE", "/users/123")
        result.should_not be_nil
        if result
          route_info, params = result
          route_info[:action].should eq(:destroy)
          params["id"].should eq("123")
        end
      end

      it "respects :only option" do
        router = Takarik::Router.new
        router.resources(:users, UsersController, only: [:index, :show])

        # Should have index and show
        router.match("GET", "/users").should_not be_nil
        router.match("GET", "/users/123").should_not be_nil

        # Should not have create, update, destroy
        router.match("POST", "/users").should be_nil
        router.match("PUT", "/users/123").should be_nil
        router.match("DELETE", "/users/123").should be_nil
      end

      it "respects :except option" do
        router = Takarik::Router.new
        router.resources(:users, UsersController, except: [:create, :destroy])

        # Should have most routes
        router.match("GET", "/users").should_not be_nil
        router.match("GET", "/users/123").should_not be_nil
        router.match("PUT", "/users/123").should_not be_nil

        # Should not have create and destroy
        router.match("POST", "/users").should be_nil
        router.match("DELETE", "/users/123").should be_nil
      end
    end

    context "within controller scope" do
      it "creates RESTful routes using current controller" do
        router = Takarik::Router.new
        router.map(UsersController) do
          resources(:users)
        end

        result = router.match("GET", "/users")
        result.should_not be_nil

        if result
          route_info, _ = result
          route_info[:controller].should eq(UsersController)
          route_info[:action].should eq(:index)
        end
      end

      it "raises error when no controller scope is set" do
        router = Takarik::Router.new
        expect_raises(Exception, "Controller scope required") do
          router.resources(:users)
        end
      end
    end

    context "with block" do
      it "allows nested routes" do
        router = Takarik::Router.new
        router.resources(:users, UsersController) do
          collection do
            get(:search)
          end

          member do
            get(:profile)
          end
        end

        # Collection route
        result = router.match("GET", "/users/search")
        result.should_not be_nil
        result.not_nil![0][:action].should eq(:search) if result

        # Member route
        result = router.match("GET", "/users/123/profile")
        result.should_not be_nil
        if result
          route_info, params = result
          route_info[:action].should eq(:profile)
          params["id"].should eq("123")
        end
      end
    end
  end

  describe "#collection" do
    it "creates collection routes within resources block" do
      router = Takarik::Router.new
      router.resources(:users, UsersController) do
        collection do
          get(:search)
          post(:bulk_create)
        end
      end

      # Collection GET route
      result = router.match("GET", "/users/search")
      result.should_not be_nil
      result.not_nil![0][:action].should eq(:search) if result

      # Collection POST route
      result = router.match("POST", "/users/bulk_create")
      result.should_not be_nil
      result.not_nil![0][:action].should eq(:bulk_create) if result
    end

    it "raises error when called outside resources block" do
      router = Takarik::Router.new
      expect_raises(Exception, "Collection can only be called within a resources block") do
        router.collection do
          get(:test)
        end
      end
    end
  end

  describe "#member" do
    it "creates member routes within resources block" do
      router = Takarik::Router.new
      router.resources(:users, UsersController) do
        member do
          get(:profile)
          post(:activate)
        end
      end

      # Member GET route
      result = router.match("GET", "/users/123/profile")
      result.should_not be_nil
      if result
        route_info, params = result
        route_info[:action].should eq(:profile)
        params["id"].should eq("123")
      end

      # Member POST route
      result = router.match("POST", "/users/456/activate")
      result.should_not be_nil
      if result
        route_info, params = result
        route_info[:action].should eq(:activate)
        params["id"].should eq("456")
      end
    end

    it "raises error when called outside resources block" do
      router = Takarik::Router.new
      expect_raises(Exception, "Member can only be called within a resources block") do
        router.member do
          get(:test)
        end
      end
    end
  end

  describe "singleton pattern" do
    it "provides a singleton instance" do
      instance1 = Takarik::Router.instance
      instance2 = Takarik::Router.instance

      instance1.should be(instance2)
    end

    it "allows defining routes through the singleton" do
      # Clear any existing routes by getting a fresh instance for this test
      Takarik::Router.define do
        get("/singleton_test", TestController, :index)
      end

      result = Takarik::Router.instance.match("GET", "/singleton_test")
      result.should_not be_nil

      if result
        route_info, _ = result
        route_info[:controller].should eq(TestController)
        route_info[:action].should eq(:index)
      end
    end
  end

  describe "named routes" do
    describe "#add_route with name" do
      it "stores named route when name is provided" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id", TestController, :show, "user_show")

        router.named_routes.has_key?("user_show").should be_true
        named_route = router.named_routes["user_show"]
        named_route[:pattern].should eq("/users/:id")
        named_route[:http_method].should eq("GET")
        named_route[:controller].should eq(TestController)
        named_route[:action].should eq(:show)
      end
    end

    describe "#path_for" do
      it "generates path from named route without parameters" do
        router = Takarik::Router.new
        router.add_route("GET", "/users", TestController, :index, "users_index")

        path = router.path_for("users_index")
        path.should eq("/users")
      end

      it "generates path from named route with parameters" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id", TestController, :show, "user_show")

        path = router.path_for("user_show", {"id" => "123"})
        path.should eq("/users/123")
      end

      it "generates path with multiple parameters" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:user_id/posts/:id", TestController, :show, "user_post")

        path = router.path_for("user_post", {"user_id" => "42", "id" => "123"})
        path.should eq("/users/42/posts/123")
      end

      it "accepts Int32 parameters" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id", TestController, :show, "user_show")

        path = router.path_for("user_show", {"id" => 123})
        path.should eq("/users/123")
      end

      it "raises error for non-existent route name" do
        router = Takarik::Router.new

        expect_raises(Exception, "No route found with name 'non_existent'") do
          router.path_for("non_existent")
        end
      end

      it "raises error for missing required parameters" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id", TestController, :show, "user_show")

        expect_raises(Exception, /Missing required parameters: id/) do
          router.path_for("user_show")
        end
      end
    end

    describe "#url_for" do
      it "returns same as path_for (since full URL generation is not implemented)" do
        router = Takarik::Router.new
        router.add_route("GET", "/users/:id", TestController, :show, "user_show")

        url = router.url_for("user_show", {"id" => "123"})
        path = router.path_for("user_show", {"id" => "123"})
        url.should eq(path)
      end
    end

    describe "class methods" do
      it "provides class-level path_for method" do
        Takarik::Router.instance.add_route("GET", "/test/:id", TestController, :show, "test_show")

        path = Takarik::Router.path_for("test_show", {"id" => "456"})
        path.should eq("/test/456")
      end

      it "provides class-level url_for method" do
        Takarik::Router.instance.add_route("GET", "/test/:id", TestController, :show, "test_show_class")

        url = Takarik::Router.url_for("test_show_class", {"id" => "789"})
        url.should eq("/test/789")
      end
    end

    describe "resource routes with auto-generated names" do
      it "generates standard RESTful route names" do
        router = Takarik::Router.new
        router.resources(:users, UsersController)

        # Check that named routes were created
        router.named_routes.has_key?("users_index").should be_true
        router.named_routes.has_key?("users_new").should be_true
        router.named_routes.has_key?("users_create").should be_true
        router.named_routes.has_key?("users_show").should be_true
        router.named_routes.has_key?("users_edit").should be_true
        router.named_routes.has_key?("users_update").should be_true
        router.named_routes.has_key?("users_patch").should be_true
        router.named_routes.has_key?("users_destroy").should be_true
      end

      it "allows path generation from resource route names" do
        router = Takarik::Router.new
        router.resources(:users, UsersController)

        router.path_for("users_index").should eq("/users")
        router.path_for("users_new").should eq("/users/new")
        router.path_for("users_show", {"id" => "123"}).should eq("/users/123")
        router.path_for("users_edit", {"id" => "456"}).should eq("/users/456/edit")
      end
    end

    describe "automatic route name generation" do
      it "generates names for routes without explicit names" do
        router = Takarik::Router.new
        router.add_route("GET", "/users", TestController, :index)
        router.add_route("POST", "/users", TestController, :create)
        router.add_route("GET", "/users/:id", TestController, :show)
        router.add_route("GET", "/users/:id/edit", TestController, :edit)

        # Check that auto-generated names exist
        router.named_routes.has_key?("users_index").should be_true
        router.named_routes.has_key?("users_create").should be_true
        router.named_routes.has_key?("users_show").should be_true
        router.named_routes.has_key?("users_edit").should be_true
      end

      it "can generate paths using auto-generated names" do
        router = Takarik::Router.new
        router.add_route("GET", "/api/v1/users/:user_id/posts/:id", TestController, :show)

        # Auto-generated name should be: api_v1_users_posts_show
        router.path_for("api_v1_users_posts_show", {"user_id" => "123", "id" => "456"}).should eq("/api/v1/users/123/posts/456")
      end

      it "prefers explicit names over auto-generated ones" do
        router = Takarik::Router.new
        router.add_route("GET", "/users", TestController, :index, "custom_users_list")

        # Should use the explicit name, not auto-generated "users"
        router.named_routes.has_key?("custom_users_list").should be_true
        router.named_routes.has_key?("users").should be_false
      end

      it "handles root path correctly" do
        router = Takarik::Router.new
        router.add_route("GET", "/", TestController, :index)

        # Root path should generate a reasonable name
        router.named_routes.has_key?("root").should be_true
      end
    end
  end
end
