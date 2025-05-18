module Takarik
  module Views
    class ECREngine < Engine
      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any))
        controller.render_template(view, locals)
      end
    end
  end
end
