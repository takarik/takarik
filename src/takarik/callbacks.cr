module Takarik
  module Callbacks
    macro before_actions(callbacks_array)
      {% callbacks = [] of Nil %}
      {% for callback_tuple in callbacks_array %}
        {% callbacks << {
          method: callback_tuple[:method],
          only: callback_tuple[:only],
          except: callback_tuple[:except]
        } %}
      {% end %}

      def run_before_action(action : Symbol) : Bool
        result = true

        {% for callback in callbacks %}
          {% method_name = callback[:method] %}
          {% only = callback[:only] %}
          {% except = callback[:except] %}

          {% if only %}
            if {{only}}.includes?(action)
              callback_result = {{method_name.id}}()
              result = result && callback_result
            end
          {% elsif except %}
            if !{{except}}.includes?(action)
              callback_result = {{method_name.id}}()
              result = result && callback_result
            end
          {% else %}
            callback_result = {{method_name.id}}()
            result = result && callback_result
          {% end %}
        {% end %}

        return result
      end
    end

    macro after_actions(callbacks_array)
      {% callbacks = [] of Nil %}
      {% for callback_tuple in callbacks_array %}
        {% callbacks << {
          method: callback_tuple[:method],
          only: callback_tuple[:only],
          except: callback_tuple[:except]
        } %}
      {% end %}

      def run_after_action(action : Symbol) : Bool
        {% for callback in callbacks %}
          {% method_name = callback[:method] %}
          {% only = callback[:only] %}
          {% except = callback[:except] %}

          {% if only %}
            if {{only}}.includes?(action)
              {{method_name.id}}()
            end
          {% elsif except %}
            if !{{except}}.includes?(action)
              {{method_name.id}}()
            end
          {% else %}
            {{method_name.id}}()
          {% end %}
        {% end %}

        return true
      end
    end
  end
end
