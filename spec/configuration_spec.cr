require "./spec_helper"

# Create test view engines for configuration specs
module Takarik
  module Views
    class TestEngine < Engine
      property rendered_calls : Array({Symbol, Hash(Symbol | String, ::JSON::Any)})

      def initialize
        @rendered_calls = [] of {Symbol, Hash(Symbol | String, ::JSON::Any)}
      end

      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any), layout : Symbol? = nil)
        # Convert the locals to ensure proper type
        converted_locals = {} of Symbol | String => ::JSON::Any
        locals.each { |k, v| converted_locals[k] = v }
        @rendered_calls << {view, converted_locals}
        "Rendered #{view}"
      end
    end

    class CustomEngine < Takarik::Views::Engine
      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any), layout : Symbol? = nil)
        "custom engine: #{view}"
      end
    end

    class AnotherEngine < Takarik::Views::Engine
      def render(controller : BaseController, view : Symbol, locals : Hash(Symbol | String, ::JSON::Any), layout : Symbol? = nil)
        "another engine: #{view}"
      end
    end
  end
end

describe "Takarik::Configuration" do
  # Reset configuration before each test
  before_each do
    Takarik.configure { |c| c.view_engine = Takarik::Views::ECREngine.new }
  end

  describe "initialization" do
    it "initializes with default ECR view engine" do
      config = Takarik::Configuration.new

      config.view_engine.should be_a(Takarik::Views::ECREngine)
      config.view_engine.should_not be_nil
    end

    it "creates a new instance each time" do
      config1 = Takarik::Configuration.new
      config2 = Takarik::Configuration.new

      config1.should_not eq(config2)
      config1.view_engine.should_not eq(config2.view_engine)
    end

    it "sets default values" do
      config = Takarik::Configuration.new

      config.view_engine.should be_a(Takarik::Views::ECREngine)
      config.static_file_handler.should be_a(Takarik::StaticFileHandler)
      config.serve_static_files?.should be_true
      config.static_url_prefix.should eq("/")
    end
  end

  describe "view engine configuration" do
    it "allows setting custom view engine" do
      config = Takarik::Configuration.new
      custom_engine = Takarik::Views::TestEngine.new

      config.view_engine = custom_engine

      config.view_engine.should eq(custom_engine)
      config.view_engine.should be_a(Takarik::Views::TestEngine)
    end

    it "allows setting view engine to nil" do
      config = Takarik::Configuration.new

      config.view_engine = nil

      config.view_engine.should be_nil
    end

    it "supports different view engine types" do
      config = Takarik::Configuration.new

      # Test with different engines
      test_engine = Takarik::Views::TestEngine.new
      config.view_engine = test_engine
      config.view_engine.should eq(test_engine)

      custom_engine = Takarik::Views::CustomEngine.new
      config.view_engine = custom_engine
      config.view_engine.should eq(custom_engine)

      another_engine = Takarik::Views::AnotherEngine.new
      config.view_engine = another_engine
      config.view_engine.should eq(another_engine)
    end
  end

  describe "singleton config access" do
    it "provides singleton access through Takarik.config" do
      config1 = Takarik.config
      config2 = Takarik.config

      config1.should eq(config2)
      config1.should be_a(Takarik::Configuration)
    end

    it "creates singleton instance with default configuration" do
      config = Takarik.config

      config.should be_a(Takarik::Configuration)
      config.view_engine.should be_a(Takarik::Views::ECREngine)
    end

    it "maintains singleton state across calls" do
      original_engine = Takarik.config.view_engine
      custom_engine = Takarik::Views::TestEngine.new

      Takarik.config.view_engine = custom_engine

      # Should maintain the custom engine in subsequent calls
      Takarik.config.view_engine.should eq(custom_engine)
      Takarik.config.view_engine.should_not eq(original_engine)
    end
  end

  describe "configure block syntax" do
    it "yields the configuration instance to block" do
      test_engine = Takarik::Views::TestEngine.new

      Takarik.configure do |config|
        config.should be_a(Takarik::Configuration)
        config.view_engine = test_engine
      end

      Takarik.config.view_engine.should eq(test_engine)
    end

    it "allows chaining configuration calls" do
      engine1 = Takarik::Views::TestEngine.new
      engine2 = Takarik::Views::CustomEngine.new

      Takarik.configure do |config|
        config.view_engine = engine1
      end

      Takarik.config.view_engine.should eq(engine1)

      Takarik.configure do |config|
        config.view_engine = engine2
      end

      Takarik.config.view_engine.should eq(engine2)
    end

    it "supports complex configuration in single block" do
      custom_engine = Takarik::Views::CustomEngine.new

      Takarik.configure do |config|
        # Multiple configuration operations
        config.view_engine = nil
        config.view_engine.should be_nil

        config.view_engine = custom_engine
        config.view_engine.should eq(custom_engine)
      end

      Takarik.config.view_engine.should eq(custom_engine)
    end

    it "works with multiple configure calls" do
      engine1 = Takarik::Views::TestEngine.new
      engine2 = Takarik::Views::CustomEngine.new
      engine3 = Takarik::Views::AnotherEngine.new

      Takarik.configure { |c| c.view_engine = engine1 }
      Takarik.config.view_engine.should eq(engine1)

      Takarik.configure { |c| c.view_engine = engine2 }
      Takarik.config.view_engine.should eq(engine2)

      Takarik.configure { |c| c.view_engine = engine3 }
      Takarik.config.view_engine.should eq(engine3)
    end
  end

  describe "configuration persistence" do
    it "maintains configuration across application lifecycle" do
      custom_engine = Takarik::Views::TestEngine.new

      # Configure
      Takarik.configure do |config|
        config.view_engine = custom_engine
      end

      # Verify configuration persists
      config1 = Takarik.config
      config2 = Takarik.config

      config1.view_engine.should eq(custom_engine)
      config2.view_engine.should eq(custom_engine)
      config1.should eq(config2)
    end

    it "allows reconfiguration" do
      # Initial configuration
      engine1 = Takarik::Views::TestEngine.new
      Takarik.configure { |c| c.view_engine = engine1 }
      Takarik.config.view_engine.should eq(engine1)

      # Reconfiguration
      engine2 = Takarik::Views::CustomEngine.new
      Takarik.configure { |c| c.view_engine = engine2 }
      Takarik.config.view_engine.should eq(engine2)

      # Should maintain the new configuration
      Takarik.config.view_engine.should eq(engine2)
      Takarik.config.view_engine.should_not eq(engine1)
    end
  end

  describe "default configuration" do
    it "uses ECR engine by default for new instances" do
      config = Takarik::Configuration.new

      config.view_engine.should be_a(Takarik::Views::ECREngine)
    end

    it "provides working default configuration" do
      # Default config should be ready to use
      config = Takarik::Configuration.new

      config.should be_a(Takarik::Configuration)
      config.view_engine.should_not be_nil
      config.view_engine.should be_a(Takarik::Views::Engine)
    end
  end

  describe "configuration validation" do
    it "accepts valid view engines" do
      valid_engines = [
        Takarik::Views::ECREngine.new,
        Takarik::Views::TestEngine.new,
        Takarik::Views::CustomEngine.new,
        Takarik::Views::AnotherEngine.new
      ]

      valid_engines.each do |engine|
        config = Takarik::Configuration.new
        config.view_engine = engine
        config.view_engine.should eq(engine)
      end
    end

    it "accepts nil view engine" do
      config = Takarik::Configuration.new

      config.view_engine = nil
      config.view_engine.should be_nil
    end
  end

  describe "integration with framework" do
    it "integrates with module-level configuration" do
      custom_engine = Takarik::Views::TestEngine.new

      # Configure at module level
      Takarik.configure do |config|
        config.view_engine = custom_engine
      end

      # Should be accessible through direct access
      Takarik.config.view_engine.should eq(custom_engine)

      # And through singleton access
      config_instance = Takarik.config
      config_instance.view_engine.should eq(custom_engine)
    end

    it "provides consistent configuration access" do
      engine = Takarik::Views::CustomEngine.new

      Takarik.configure { |c| c.view_engine = engine }

      # Multiple access methods should return same configuration
      config1 = Takarik.config
      config2 = Takarik.config

      config1.should eq(config2)
      config1.view_engine.should eq(config2.view_engine)
      config1.view_engine.should eq(engine)
    end
  end

  describe "configuration state management" do
    it "maintains state across different operations" do
      original_engine = Takarik.config.view_engine
      test_engine = Takarik::Views::TestEngine.new

      # Change configuration
      Takarik.config.view_engine = test_engine
      Takarik.config.view_engine.should eq(test_engine)

      # Access through configure block
      Takarik.configure do |config|
        config.view_engine.should eq(test_engine)
        config.view_engine.should_not eq(original_engine)
      end

      # State should persist
      Takarik.config.view_engine.should eq(test_engine)
    end

    it "handles rapid configuration changes" do
      engines = [
        Takarik::Views::TestEngine.new,
        Takarik::Views::CustomEngine.new,
        Takarik::Views::AnotherEngine.new
      ]

      engines.each_with_index do |engine, index|
        Takarik.configure { |c| c.view_engine = engine }
        Takarik.config.view_engine.should eq(engine)

        # Verify previous engines are not retained
        engines.each_with_index do |prev_engine, prev_index|
          if prev_index < index
            Takarik.config.view_engine.should_not eq(prev_engine)
          end
        end
      end
    end
  end

  describe "#static_files" do
    it "configures static file serving" do
      config = Takarik::Configuration.new

      config.static_files(
        public_dir: "./assets",
        cache_control: "public, max-age=86400",
        url_prefix: "/static",
        enable_etag: false,
        enable_last_modified: false,
        index_files: ["home.html"]
      )

      config.serve_static_files?.should be_true
      config.static_url_prefix.should eq("/static")

      handler = config.static_file_handler.not_nil!
      handler.public_dir.should eq("./assets")
      handler.cache_control.should eq("public, max-age=86400")
      handler.enable_etag.should be_false
      handler.enable_last_modified.should be_false
      handler.index_files.should eq(["home.html"])
    end
  end

  describe "#disable_static_files!" do
    it "disables static file serving" do
      config = Takarik::Configuration.new

      # Should start enabled
      config.serve_static_files?.should be_true
      config.static_file_handler.should_not be_nil

      # Disable it
      config.disable_static_files!

      # Should now be disabled
      config.serve_static_files?.should be_false
      config.static_file_handler.should be_nil
    end
  end
end
