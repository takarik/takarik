# takarik

A lightweight web framework for Crystal, providing routing, controllers, and views.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     takarik:
       github: your-github-user/takarik
   ```

2. Run `shards install`

## Usage

```crystal
require "takarik"
```

Create controllers, define routes, and start your application:

```crystal
class HomeController < Takarik::BaseController
  actions :index

  def index
    render plain: "Hello, World!"
  end
end

class UsersController < Takarik::BaseController
  actions :index, :show, :new, :create, :edit, :update, :destroy, :refresh

  def index
    render plain: "List of users"
  end

  def show
    render plain: "User #{params["id"]}"
  end

  def new
    render plain: "New user form"
  end

  def create
    # Process form submission
    render plain: "User created"
  end

  def edit
    # Implementation needed
  end

  def update
    # Implementation needed
  end

  def destroy
    # Implementation needed
  end

  def refresh
    # Custom member action
    render plain: "Refreshing data for user #{params["id"]}"
  end
end

app = Takarik::Application.new

# Define routes
app.router.define do
  # Simple routes
  get "/", controller: HomeController, action: :index

  # Controller-scoped routes
  map UsersController do
    # RESTful resource routes (creates 7 standard routes)
    resources :users do
      # Custom member routes (operate on a specific resource)
      member do
        get "/refresh", action: :refresh
      end
    end

    # With filtering
    resources :posts, only: [:index, :show]
    resources :comments, except: [:destroy]
  end
end

app.run
```

### Resource Routing

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

#### Custom Resource Routes

You can add custom routes to resources:

```crystal
resources :users do
  # Routes that operate on a specific user
  member do
    get "/refresh", action: :refresh        # Creates GET /users/:id/refresh
    post "/send_email", action: :send_email # Creates POST /users/:id/send_email
  end
end
```

## Development

Run tests with `crystal spec`

## Contributing

1. Fork it (<https://github.com/your-github-user/takarik/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Sinan Keskin](https://github.com/your-github-user) - creator and maintainer
