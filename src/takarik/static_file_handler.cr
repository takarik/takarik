require "http/server"
require "file"
require "digest/md5"
require "log"
require "./mime_types"

module Takarik
  class StaticFileHandler
    property public_dir : String
    property cache_control : String
    property index_files : Array(String)
    property enable_etag : Bool
    property enable_last_modified : Bool
    property enable_compression : Bool

    def initialize(
      @public_dir = "./public",
      @cache_control = "public, max-age=3600",
      @index_files = ["index.html", "index.htm"],
      @enable_etag = true,
      @enable_last_modified = true,
      @enable_compression = false
    )
    end

        def call(context : HTTP::Server::Context) : Bool
      request = context.request
      response = context.response
      request_path = request.path.not_nil!

      # Only handle GET and HEAD requests
      return false unless ["GET", "HEAD"].includes?(request.method)

      # Get the file path from the request
      file_path = get_file_path(request_path)
      return false unless file_path

      # Security check: ensure the file is within the public directory
      return false unless safe_path?(file_path)

      # Check if file exists
      return false unless File.exists?(file_path)

      # Handle directory requests
      if File.directory?(file_path)
        index_file = find_index_file(file_path)
        return false unless index_file
        file_path = index_file
      end

      # Get file info
      file_info = File.info(file_path)
      return false unless file_info.file?

      # Set content type
      content_type = MimeTypes.mime_type_for(file_path)
      response.content_type = content_type

      # Handle conditional requests (If-None-Match, If-Modified-Since)
      if handle_conditional_request(context, file_path, file_info)
        return true
      end

      # Set caching headers
      set_caching_headers(response, file_path, file_info)

      # Handle HEAD requests (no body)
      if request.method == "HEAD"
        response.content_length = file_info.size
        return true
      end

      # Serve the file
      serve_file(response, file_path, file_info)

      Log.debug { "Static file served: #{file_path}" }
      true
    rescue ex : File::Error
      Log.warn(exception: ex) { "Error serving static file: #{request_path}" }
      false
    rescue ex
      Log.error(exception: ex) { "Unexpected error serving static file: #{request_path}" }
      false
    end

    private def get_file_path(request_path : String) : String?
      # Remove query string and decode path
      path = request_path.split('?').first
      decoded_path = URI.decode(path)

      # Remove leading slash and join with public directory
      clean_path = decoded_path.lstrip('/')
      File.join(@public_dir, clean_path)
    end

        private def safe_path?(file_path : String) : Bool
      # Resolve both paths to absolute paths to prevent directory traversal
      begin
        real_public_dir = Path[@public_dir].expand.to_s
        real_file_path = Path[File.dirname(file_path)].expand.to_s
        file_name = File.basename(file_path)
        full_real_path = File.join(real_file_path, file_name)

        # Check if the resolved file path is within the public directory
        full_real_path.starts_with?(real_public_dir)
      rescue File::Error
        # If we can't resolve the path, it's probably invalid
        false
      end
    end

    private def find_index_file(dir_path : String) : String?
      @index_files.each do |index_file|
        full_path = File.join(dir_path, index_file)
        return full_path if File.exists?(full_path) && File.file?(full_path)
      end
      nil
    end

    private def handle_conditional_request(context : HTTP::Server::Context, file_path : String, file_info : File::Info) : Bool
      request = context.request
      response = context.response

      # Handle If-None-Match (ETag)
      if @enable_etag && (if_none_match = request.headers["If-None-Match"]?)
        etag = generate_etag(file_path, file_info)
        if if_none_match == etag || if_none_match == "*"
          response.status = :not_modified
          response.headers["ETag"] = etag
          return true
        end
      end

      # Handle If-Modified-Since
      if @enable_last_modified && (if_modified_since = request.headers["If-Modified-Since"]?)
        begin
          client_time = HTTP.parse_time(if_modified_since)
          if client_time && file_info.modification_time <= client_time
            response.status = :not_modified
            return true
          end
        rescue Time::Format::Error
          # Invalid date format, ignore
        end
      end

      false
    end

    private def set_caching_headers(response : HTTP::Server::Response, file_path : String, file_info : File::Info)
      # Set Cache-Control
      response.headers["Cache-Control"] = @cache_control

      # Set ETag
      if @enable_etag
        response.headers["ETag"] = generate_etag(file_path, file_info)
      end

      # Set Last-Modified
      if @enable_last_modified
        response.headers["Last-Modified"] = HTTP.format_time(file_info.modification_time)
      end

      # Set Content-Length
      response.content_length = file_info.size
    end

    private def generate_etag(file_path : String, file_info : File::Info) : String
      # Generate ETag based on file path, size, and modification time
      content = "#{file_path}:#{file_info.size}:#{file_info.modification_time.to_unix}"
      etag = Digest::MD5.hexdigest(content)[0, 16]
      %("#{etag}")
    end

    private def serve_file(response : HTTP::Server::Response, file_path : String, file_info : File::Info)
      # For small files, read into memory. For large files, stream.
      if file_info.size <= 1_048_576 # 1MB threshold
        content = File.read(file_path)
        response.print(content)
      else
        # Stream large files
        File.open(file_path, "r") do |file|
          IO.copy(file, response)
        end
      end
    end

    # Utility method to check if a path should be handled as static
    def self.static_path?(path : String, static_url_prefix : String = "/") : Bool
      return true if static_url_prefix == "/"
      path.starts_with?(static_url_prefix)
    end
  end
end
