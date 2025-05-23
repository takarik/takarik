module Takarik
  module Views
    module ECRRenderer
      macro layouts(*layouts)
        def render_layout(layout : Symbol, content : String, locals : Hash(Symbol | String, ::JSON::Any) = {} of Symbol => ::JSON::Any)
          @content = content
          {% begin %}
            case layout
            {% for layout in layouts %}
            when {{layout}}
              ECR.render("./app/views/layouts/{{layout.id}}.ecr")
            {% end %}
            else
              raise "Unknown layout: #{layout}"
            end
          {% end %}
        end
      end

      macro views(*views)
        {% controller_path = @type.name.gsub(/Controller$/, "").underscore %}

        def render_view(view : Symbol, locals : Hash(Symbol | String, ::JSON::Any) = {} of Symbol => ::JSON::Any, layout : Symbol? = nil)
          # Render the view content first
          view_content = {% begin %}
            case view
            {% for view in views %}
            when {{view}}
              ECR.render("./app/views/{{controller_path.id}}/{{view.id}}.ecr")
            {% end %}
            else
              raise "Unknown view: #{view}"
            end
          {% end %}

          # If layout is specified and render_layout method exists, wrap in layout
          if layout && responds_to?(:render_layout)
            render_layout(layout, view_content, locals)
          else
            view_content
          end
        end
      end
    end
  end
end
