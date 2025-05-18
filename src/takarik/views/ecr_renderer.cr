module Takarik
  module Views
    module ECRRenderer
      macro views(*views)
        {% controller_path = @type.name.gsub(/Controller$/, "").underscore %}

        def render_template(view : Symbol, locals : Hash(Symbol | String, ::JSON::Any) = {} of Symbol => ::JSON::Any)
          {% begin %}
            case view
            {% for view in views %}
            when {{view}}
              ECR.render("app/views/{{controller_path.id}}/{{view.id}}.ecr")
            {% end %}
            else
              raise "Unknown view: #{view}"
            end
          {% end %}
        end
      end
    end
  end
end
