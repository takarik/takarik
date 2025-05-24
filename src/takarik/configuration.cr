require "./views/engine" # Require the engine interface
require "./static_file_handler"

module Takarik
  class Configuration
    property view_engine : Takarik::Views::Engine?
    property static_file_handler : StaticFileHandler?
    property static_url_prefix : String

    def initialize
      @view_engine = Takarik::Views::ECREngine.new
      @static_file_handler = StaticFileHandler.new
      @serve_static_files = true
      @static_url_prefix = "/"
    end

    def serve_static_files? : Bool
      @serve_static_files
    end

    private def serve_static_files=(value : Bool)
      @serve_static_files = value
    end

    # Helper method to configure static file serving
    def static_files(
      public_dir : String = "./public",
      cache_control : String = "public, max-age=3600",
      url_prefix : String = "/",
      enable_etag : Bool = true,
      enable_last_modified : Bool = true,
      index_files : Array(String) = ["index.html", "index.htm"]
    )
      @static_file_handler = StaticFileHandler.new(
        public_dir: public_dir,
        cache_control: cache_control,
        enable_etag: enable_etag,
        enable_last_modified: enable_last_modified,
        index_files: index_files
      )
      @static_url_prefix = url_prefix
      self.serve_static_files = true
    end

    # Disable static file serving
    def disable_static_files!
      self.serve_static_files = false
      @static_file_handler = nil
    end
  end

  def self.config
    @@config ||= Configuration.new
  end

  def self.configure(&)
    yield config
  end
end
