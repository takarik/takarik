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

  layouts :application, :minimal  # Defines which layouts this controller can use
  views :index, :show  # Defines which views this controller can render
  actions :index, :show

  def index
    @users = ["Alice", "Bob", "Charlie"]
    render view: :index, layout: :application
  end

  def show
    @user = "User #{params["id"]}"
    render view: :show, locals: locals(
      title: "User Profile",
      user_id: params["id"],
      is_admin: true,
      tags: ["user", "profile", "active"]
    ), layout: :minimal
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

#### Layout Templates

Create layout templates in `./app/views/layouts/`:

```erb
<!-- ./app/views/layouts/application.ecr -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title><%= locals["title"]? || "My App" %></title>
</head>
<body>
  <header>
    <h1>My Application</h1>
  </header>

  <main>
    <%= @content %>
  </main>

  <footer>
    <p>&copy; 2024 My App</p>
  </footer>
</body>
</html>
```

```erb
<!-- ./app/views/layouts/minimal.ecr -->
<!DOCTYPE html>
<html>
<head>
  <title><%= locals["title"]? || "App" %></title>
</head>
<body>
  <%= @content %>
</body>
</html>
```

The `@content` variable contains the rendered view content that gets inserted into the layout.

**Layout Usage:**
- Use the `layouts` macro to declare which layouts your controller can use (similar to `views`)
- Specify layout in render calls: `render view: :index, layout: :application`
- If no layout is specified in render, no layout will be applied
- Layouts must be declared in the `layouts` macro for ECR compile-time requirements

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

  # Callbacks - Use individual DSL syntax (recommended) or array syntax
  before_action :authenticate_user
  before_action :load_user, only: [:show, :destroy]
  after_action :log_activity, except: [:index]

  # Alternative array syntax (legacy):
  # before_actions [
  #   {method: :authenticate_user, only: nil, except: nil},
  #   {method: :load_user, only: [:show, :destroy], except: nil}
  # ]
  # after_actions [
  #   {method: :log_activity, only: nil, except: [:index]}
  # ]

  def index
    render json: ["user1", "user2"]
  end

  def show
    render json: {"id" => params["id"], "name" => "User #{params["id"]}"}
  end

  def create
    # Create user logic here
    render status: :created
  end

  def destroy
    # Delete user
    head :no_content
  end

  def profile
    render plain: "Profile for user #{params["id"]}"
  end

  def search
    query = params["q"]?
    render json: locals(
      query: query || "",
      results: ["Alice", "Bob"].select(&.downcase.includes?((query || "").downcase)),
      total: 2
    )
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

Takarik supports before and after action callbacks with flexible filtering. You can use either individual DSL calls (Rails-style) or array-based syntax:

##### Individual DSL Syntax (Recommended)

```crystal
class MyController < Takarik::BaseController
  # Include the callbacks module
  include Takarik::Callbacks

  # Individual callback declarations (clean, Rails-like syntax)
  before_action :authenticate                                    # Run on all actions
  before_action :load_resource, only: [:show, :update, :destroy]    # Run only on specified actions
  before_action :check_permissions, except: [:index, :show]         # Run on all except specified actions

  after_action :log_action                                      # Run on all actions
  after_action :cleanup, only: [:destroy]                      # Run only on destroy

  # You can mix and match - add more callbacks anywhere in the controller
  before_action :validate_request, only: [:create, :update]

  def index
    # Action logic
  end

  def show
    # Action logic
  end

  def create
    # Action logic
  end

  def update
    # Action logic
  end

  def destroy
    # Action logic
  end

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

  private def validate_request
    # Validation logic
    true
  end

  private def log_action
    puts "Action #{@current_action_name} completed"
  end

  private def cleanup
    # Cleanup logic
  end
end
```

##### Array-Based Syntax (Legacy)

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
```

##### Callback Features

- **Execution Order**: Callbacks execute in the order they are defined
- **Action Filtering**:
  - `only: [:action1, :action2]` - Run only on specified actions
  - `except: [:action1, :action2]` - Run on all actions except specified ones
  - No filter (or `only: nil, except: nil`) - Run on all actions
- **Halting Execution**: Before callbacks can halt execution by returning `false`
- **Mixed Syntax**: You can use both individual and array syntax in the same controller
- **Backward Compatibility**: The array syntax continues to work unchanged

##### Choosing Your Syntax

- **Individual DSL**: Use for new code - cleaner, more readable, Rails-familiar
- **Array Syntax**: Use when migrating from older versions or when you need all callbacks defined in one place
- **Mixed Approach**: Use individual syntax for most callbacks, array syntax for complex conditional logic

Both approaches produce identical behavior and performance.

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
render view: :show, locals: locals(title: "Page Title", count: 42)

# Using the locals helper for automatic type conversion
render view: :profile, locals: locals(
  user_name: "John Doe",
  email: "john@example.com",
  is_admin: true,
  scores: [85, 92, 78],
  metadata: {"role" => "user", "active" => true}
)
```

**Locals Helper:**
The `locals` helper automatically converts common Crystal types to the required `JSON::Any` format:
- `String`, `Int`, `Float`, `Bool` → Converted automatically
- `Array` → Each element converted recursively
- `Hash` → Keys converted to strings, values converted recursively
- `JSON::Any` → Passed through unchanged

```crystal
# Instead of this verbose syntax:
locals_hash = {
  "name" => JSON::Any.new("John"),
  "age" => JSON::Any.new(25),
  "active" => JSON::Any.new(true)
} of Symbol | String => JSON::Any

# Use this simple syntax:
locals(name: "John", age: 25, active: true)
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

### Static File Serving

Takarik includes comprehensive static file serving capabilities with security, performance, and caching features built-in.

#### Basic Usage

Static file serving is enabled by default and serves files from the `./public` directory:

```crystal
# Static files are served automatically from ./public
# GET /css/style.css → serves ./public/css/style.css
# GET /js/app.js → serves ./public/js/app.js
# GET / → serves ./public/index.html (if it exists)
```

#### Configuration

Configure static file serving with custom options:

```crystal
Takarik.configure do |config|
  config.static_files(
    public_dir: "./assets",                    # Custom directory
    cache_control: "public, max-age=86400",   # Cache for 24 hours
    url_prefix: "/static",                     # Only serve files under /static
    enable_etag: true,                         # Enable ETag headers
    enable_last_modified: true,                # Enable Last-Modified headers
    index_files: ["index.html", "index.htm"]  # Directory index files
  )
end
```

#### Disable Static File Serving

```crystal
Takarik.configure do |config|
  config.disable_static_files!
end
```

#### Features

- **Security**: Protection against directory traversal attacks
- **Performance**: ETag and Last-Modified headers for efficient caching
- **MIME Types**: Automatic content-type detection for 30+ file types
- **Conditional Requests**: Returns 304 Not Modified when appropriate
- **Directory Index**: Automatic serving of index files for directories
- **Streaming**: Efficient serving of large files with streaming
- **URL Decoding**: Proper handling of URL-encoded file names

#### Supported File Types

Static file serving automatically detects MIME types for:

- **Web Assets**: `.html`, `.css`, `.js`, `.json`, `.xml`
- **Images**: `.png`, `.jpg`, `.gif`, `.svg`, `.webp`, `.ico`
- **Fonts**: `.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`
- **Documents**: `.pdf`, `.txt`, `.md`
- **Media**: `.mp3`, `.mp4`, `.webm`, `.ogg`, `.wav`
- **Archives**: `.zip`, `.tar`, `.gz`
- **Other**: `.map` (source maps), `.wasm` (WebAssembly)

#### Directory Structure

```
your_app/
├── public/
│   ├── css/
│   │   └── style.css
│   ├── js/
│   │   └── app.js
│   ├── images/
│   │   └── logo.png
│   └── index.html
└── app/
    └── ...
```

#### Complete Example

Here's a complete application showcasing all features:

```crystal
require "takarik"

# Home controller with view rendering
class HomeController < Takarik::BaseController
  include Takarik::Views::ECRRenderer

  layouts :application
  views :index
  actions :index

  def index
    @message = "Welcome to Takarik!"
    render view: :index, layout: :application
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
    render json: locals(
      query: query || "",
      results: ["Alice", "Bob"].select(&.downcase.includes?((query || "").downcase)),
      total: 2
    )
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

  # Configure static file serving
  config.static_files(
    public_dir: "./public",
    cache_control: "public, max-age=3600",
    enable_etag: true
  )

  # Or disable static file serving
  # config.disable_static_files!
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