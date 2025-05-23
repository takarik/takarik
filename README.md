# takarik

A lightweight web framework for Crystal, providing routing, controllers, and views.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     takarik:
       github: takarik/takarik
   ```

2. Run `shards install`

## Usage

```crystal
require "takarik"
```

### Basic Application Setup

Create controllers, define routes, and start your application:

```crystal
class HomeController < Takarik::BaseController
  actions :index

  def index
    render plain: "Hello, World!"
  end
end

# Start your application
app = Takarik::Application.new
app.router.define do
  get "/", controller: HomeController, action: :index
end
app.run
```

### Views and Templates

Takarik supports view rendering with ECR (Embedded Crystal) templates by default:

```crystal
class UsersController < Takarik::BaseController
  include Takarik::Views::ECRRenderer

  actions :index, :show
  views :index, :show  # Defines which views this controller can render

  def index
    @users = ["Alice", "Bob", "Charlie"]
    render view: :index
  end

  def show
    @user = "User #{params["id"]}"
    render view: :show, locals: {
      "title" => JSON::Any.new("User Profile"),
      "user_id" => JSON::Any.new(params["id"])
    }
  end
end
```

Create your view templates in `./app/views/`:

```erb
<!-- ./app/views/users/index.ecr -->
<h1>Users</h1>
<ul>
<% @users.each do |user| %>
  <li><%= user %></li>
<% end %>
</ul>
```

```erb
<!-- ./app/views/users/show.ecr -->
<h1><%= locals["title"] %></h1>
<p>Viewing user: <%= @user %></p>
<p>User ID: <%= locals["user_id"] %></p>
```

#### Custom View Engines

You can also create custom view engines:

```crystal
class MyCustomEngine < Takarik::Views::Engine
  def render(controller : Takarik::BaseController, view : Symbol, locals : Hash(Symbol | String, JSON::Any))
    "Custom rendered: #{view} with #{locals.size} locals"
  end
end

# Configure your custom engine
Takarik.configure do |config|
  config.view_engine = MyCustomEngine.new
end
```

### Controller Features

Controllers support various rendering options and callbacks:

```crystal
class UsersController < Takarik::BaseController
  actions :index, :show, :create, :destroy

  # Callbacks - executed before/after actions
  before_actions [
    {method: :authenticate_user, only: nil, except: nil},
    {method: :load_user, only: [:show, :destroy], except: nil}
  ]
  after_actions [
    {method: :log_activity, only: nil, except: [:index]}
  ]

  def index
    render json: ["user1", "user2"]
  end

  def show
    render plain: "User: #{@user}"
  end

  def create
    # Process creation
    render status: 201
  end

  def destroy
    # Delete user
    head :no_content
  end

  private

  def authenticate_user
    # Authentication logic
    return true
  end

  def load_user
    @user = params["id"]
    return true
  end

  def log_activity
    puts "Action completed: #{@current_action_name}"
    return true
  end
end
```

#### Callbacks

Takarik supports before and after action callbacks with flexible filtering:

```crystal
class MyController < Takarik::BaseController
  # Include the callbacks module
  include Takarik::Callbacks

  # Define callbacks with array syntax
  before_actions [
    {method: :authenticate, only: nil, except: nil},                    # Run on all actions
    {method: :load_resource, only: [:show, :update, :destroy], except: nil},  # Run only on specified actions
    {method: :check_permissions, only: nil, except: [:index, :show]}   # Run on all except specified actions
  ]

  after_actions [
    {method: :log_action, only: nil, except: nil},
    {method: :cleanup, only: [:destroy], except: nil}
  ]

  private def authenticate
    # Return false to halt execution
    return false unless authenticated?
    true
  end

  private def load_resource
    @resource = find_resource(params["id"])
    true
  end

  private def check_permissions
    # Callback logic here
    true
  end

  private def log_action
    puts "Action #{@current_action_name} completed"
  end

  private def cleanup
    # Cleanup logic
  end
end

#### Rendering Options

Controllers support multiple rendering formats:

```crystal
# Plain text
render plain: "Hello World"

# JSON response
render json: {"message" => "success"}

# Status codes
render status: :created
render status: 404

# Head response (headers only)
head :ok
head :not_found

# View templates (with ECRRenderer)
render view: :index
render view: :show, locals: {"title" => JSON::Any.new("Page Title")}
```

### Routing

Takarik provides flexible routing with support for RESTful resources:

```crystal
app = Takarik::Application.new

app.router.define do
  # Basic routes
  get "/", controller: HomeController, action: :index

  # RESTful resources
  resources :users, controller: UsersController do
    member do
      get "/profile", action: :profile
      post "/activate", action: :activate
    end

    collection do
      get "/search", action: :search
    end
  end

  # Controller-scoped routes
  map AdminController do
    get "/admin/dashboard", action: :dashboard
    resources :admin_users, only: [:index, :show]
  end

  # Resource filtering
  resources :posts, only: [:index, :show, :create]
  resources :comments, except: [:destroy]
end

app.run
```

#### Complete Example

Here's a complete application showcasing all features:

```crystal
require "takarik"

# Home controller with view rendering
class HomeController < Takarik::BaseController
  include Takarik::Views::ECRRenderer

  actions :index
  views :index

  def index
    @message = "Welcome to Takarik!"
    render view: :index
  end
end

# Users controller with callbacks and various render options
class UsersController < Takarik::BaseController
  actions :index, :show, :create, :profile, :search

  before_actions [
    {method: :authenticate, only: nil, except: [:index]}
  ]
  after_actions [
    {method: :log_action, only: nil, except: nil}
  ]

  def index
    render json: [
      {"id" => 1, "name" => "Alice"},
      {"id" => 2, "name" => "Bob"}
    ]
  end

  def show
    render json: {"id" => params["id"], "name" => "User #{params["id"]}"}
  end

  def create
    # Create user logic here
    render status: :created
  end

  def profile
    render plain: "Profile for user #{params["id"]}"
  end

  def search
    query = params["q"]?
    render json: {"query" => query, "results" => ["result1", "result2"]}
  end

  private

  def authenticate
    # Add authentication logic
    true
  end

  def log_action
    puts "Executed action: #{@current_action_name}"
    true
  end
end

# Create and configure application
app = Takarik::Application.new

# Configure view engine (optional - ECR is default)
Takarik.configure do |config|
  config.view_engine = Takarik::Views::ECREngine.new
end

# Define routes
app.router.define do
  get "/", controller: HomeController, action: :index

  resources :users, controller: UsersController do
    member do
      get "/profile", action: :profile
    end

    collection do
      get "/search", action: :search
    end
  end
end

# Start the server
app.run  # Defaults to 0.0.0.0:3000
```

Create your view template:

```erb
<!-- ./app/views/home/index.ecr -->
<!DOCTYPE html>
<html>
<head>
  <title>Takarik App</title>
</head>
<body>
  <h1><%= @message %></h1>
  <p>Your Takarik application is running!</p>
</body>
</html>
```

## Development

Run tests with `crystal spec`

#### RESTful Routing Conventions

The `resources` method creates RESTful routes following Rails conventions:

| HTTP Verb | Path | Controller#Action | Purpose |
|-----------|------|-------------------|---------|
| GET | /resources | #index | List all resources |
| GET | /resources/new | #new | Form to create a new resource |
| POST | /resources | #create | Create a resource |
| GET | /resources/:id | #show | Show a specific resource |
| GET | /resources/:id/edit | #edit | Form to edit a resource |
| PATCH/PUT | /resources/:id | #update | Update a resource |
| DELETE | /resources/:id | #destroy | Delete a resource |

## Configuration

Configure your application with various options:

```crystal
Takarik.configure do |config|
  # Set custom view engine
  config.view_engine = MyCustomEngine.new

  # Or use default ECR engine
  config.view_engine = Takarik::Views::ECREngine.new
end

# Start application with custom host/port
app = Takarik::Application.new("127.0.0.1", 4000)
app.run
```

## Development

Run tests with `crystal spec`

## Contributing

1. Fork it (<https://github.com/takarik/takarik/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Sinan Keskin](https://github.com/sinankeskin) - creator and maintainer