module Takarik
  module Views
    class ECREngine < Engine
      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any), layout : Symbol? = nil)
        # Check if controller supports render_view (ECRRenderer)
        if controller.responds_to?(:render_view)
          controller.render_view(view, locals, layout)
        else
          # Fallback for controllers without ECRRenderer
          "View rendering not available (ECRRenderer not included)"
        end
      end
    end
  end
end
