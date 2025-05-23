module Takarik
  module Callbacks
    # Simple direct approach: each callback generates its own method with a standard name pattern
    # and we call all methods matching the pattern

    macro before_action(method_name, only = nil, except = nil)
      {% only_str = only ? only.stringify.gsub(/[^a-zA-Z0-9]/, "") : "nil" %}
      {% except_str = except ? except.stringify.gsub(/[^a-zA-Z0-9]/, "") : "nil" %}
      {% callback_id = "#{method_name.id}_#{only_str}_#{except_str}".gsub(/\"/, "").id %}

      private def _before_{{callback_id}}(action : Symbol) : Bool
        {% if only %}
          return true unless {{only}}.includes?(action)
        {% end %}
        {% if except %}
          return true if {{except}}.includes?(action)
        {% end %}

        return {{method_name.id}}()
      end

      # Override/redefine the run method each time to include all currently defined callbacks
      def run_before_action(action : Symbol) : Bool
        result = true

        # Call all existing callback methods found via introspection
        {% for method in @type.methods %}
          {% if method.name.stringify.starts_with?("_before_") %}
            callback_result = {{method.name.id}}(action)
            result = result && callback_result
          {% end %}
        {% end %}

        # Also call the callback method we just defined (not yet visible in @type.methods)
        callback_result = _before_{{callback_id}}(action)
        result = result && callback_result

        return result
      end
    end

    macro after_action(method_name, only = nil, except = nil)
      {% only_str = only ? only.stringify.gsub(/[^a-zA-Z0-9]/, "") : "nil" %}
      {% except_str = except ? except.stringify.gsub(/[^a-zA-Z0-9]/, "") : "nil" %}
      {% callback_id = "#{method_name.id}_#{only_str}_#{except_str}".gsub(/\"/, "").id %}

      private def _after_{{callback_id}}(action : Symbol)
        {% if only %}
          return unless {{only}}.includes?(action)
        {% end %}
        {% if except %}
          return if {{except}}.includes?(action)
        {% end %}

        {{method_name.id}}()
      end

      # Override/redefine the run method each time to include all currently defined callbacks
      def run_after_action(action : Symbol) : Bool
        # Call all existing callback methods found via introspection
        {% for method in @type.methods %}
          {% if method.name.stringify.starts_with?("_after_") %}
            {{method.name.id}}(action)
          {% end %}
        {% end %}

        # Also call the callback method we just defined (not yet visible in @type.methods)
        _after_{{callback_id}}(action)

        return true
      end
    end

    # Legacy array-based syntax for backward compatibility
    macro before_actions(callbacks_array)
      {% callbacks = [] of Nil %}
      {% for callback_tuple in callbacks_array %}
        {% callbacks << {
             method: callback_tuple[:method],
             only:   callback_tuple[:only],
             except: callback_tuple[:except],
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
             only:   callback_tuple[:only],
             except: callback_tuple[:except],
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
