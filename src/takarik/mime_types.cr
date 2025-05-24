module Takarik
  module MimeTypes
    # Common MIME types for static assets
    MIME_TYPES = {
      # Web assets
      ".html" => "text/html",
      ".htm"  => "text/html",
      ".css"  => "text/css",
      ".js"   => "application/javascript",
      ".json" => "application/json",
      ".xml"  => "application/xml",

      # Images
      ".png"  => "image/png",
      ".jpg"  => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif"  => "image/gif",
      ".svg"  => "image/svg+xml",
      ".webp" => "image/webp",
      ".ico"  => "image/x-icon",
      ".bmp"  => "image/bmp",

      # Fonts
      ".woff"  => "font/woff",
      ".woff2" => "font/woff2",
      ".ttf"   => "font/ttf",
      ".otf"   => "font/otf",
      ".eot"   => "application/vnd.ms-fontobject",

      # Audio/Video
      ".mp3"  => "audio/mpeg",
      ".mp4"  => "video/mp4",
      ".webm" => "video/webm",
      ".ogg"  => "audio/ogg",
      ".wav"  => "audio/wav",

      # Documents
      ".pdf"  => "application/pdf",
      ".txt"  => "text/plain",
      ".md"   => "text/markdown",

      # Archives
      ".zip"  => "application/zip",
      ".tar"  => "application/x-tar",
      ".gz"   => "application/gzip",

      # Other
      ".map"  => "application/json", # Source maps
      ".wasm" => "application/wasm",
    }

    DEFAULT_MIME_TYPE = "application/octet-stream"

    def self.mime_type_for(file_path : String) : String
      extension = File.extname(file_path).downcase
      MIME_TYPES[extension]? || DEFAULT_MIME_TYPE
    end

    def self.text_mime_type?(mime_type : String) : Bool
      mime_type.starts_with?("text/") ||
      ["application/javascript", "application/json", "application/xml", "image/svg+xml"].includes?(mime_type)
    end
  end
end
