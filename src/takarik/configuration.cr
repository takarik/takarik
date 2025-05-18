require "./views/engine" # Require the engine interface

module Takarik
  class Configuration
    property view_engine : Takarik::Views::Engine?

    def initialize
      @view_engine = Takarik::Views::ECREngine.new
    end
  end

  def self.config
    @@config ||= Configuration.new
  end

  def self.configure(&)
    yield config
  end
end
