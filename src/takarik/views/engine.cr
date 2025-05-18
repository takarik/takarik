module Takarik
  module Views
    abstract class Engine
      abstract def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any))
    end
  end
end
