require "./views/engine" # Require the engine interface
require "./static_file_handler"
require "./session/store"
require "./session/memory_store"
require "./session/cookie_store"

module Takarik
  class Configuration
    property view_engine : Takarik::Views::Engine?
    property static_file_handler : StaticFileHandler?
    property static_url_prefix : String
    property session_store : Session::Store?
    property session_cookie_name : String
    property session_cookie_secure : Bool
    property session_cookie_http_only : Bool
    property session_cookie_same_site : String

    def initialize
      @view_engine = Takarik::Views::ECREngine.new
      @static_file_handler = StaticFileHandler.new
      @serve_static_files = true
      @static_url_prefix = "/"
      @session_store = Session::MemoryStore.new
      @session_cookie_name = "_takarik_session"
      @session_cookie_secure = false  # Set to true in production with HTTPS
      @session_cookie_http_only = true
      @session_cookie_same_site = "Lax"
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

    # Configure session management
    def sessions(
      store : Session::Store? = nil,
      cookie_name : String = "_takarik_session",
      secure : Bool = false,
      http_only : Bool = true,
      same_site : String = "Lax"
    )
      @session_store = store || Session::MemoryStore.new
      @session_cookie_name = cookie_name
      @session_cookie_secure = secure
      @session_cookie_http_only = http_only
      @session_cookie_same_site = same_site
    end

    # Disable session management
    def disable_sessions!
      @session_store = nil
    end

    # Check if sessions are enabled
    def sessions_enabled? : Bool
      !@session_store.nil?
    end

    # Helper methods for common session configurations
    def use_memory_sessions(max_age : Time::Span = 24.hours)
      @session_store = Session::MemoryStore.new(max_age)
    end

    def use_cookie_sessions(secret_key : String, max_size : Int32 = 4096)
      @session_store = Session::CookieStore.new(secret_key, max_size: max_size)
    end
  end

  def self.config
    @@config ||= Configuration.new
  end

  def self.configure(&)
    yield config
  end
end
