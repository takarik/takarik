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

app = Takarik::Application.new
app.router.define do |map|
  map.get "/", controller: HomeController, action: :index
end

app.run
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
