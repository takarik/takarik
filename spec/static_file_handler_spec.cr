require "./spec_helper"
require "file_utils"

# Helper to create a test HTTP context
def create_static_test_context(method = "GET", path = "/", headers = HTTP::Headers.new)
  request = HTTP::Request.new(method, path, headers)
  response_io = IO::Memory.new
  response = HTTP::Server::Response.new(response_io)
  HTTP::Server::Context.new(request, response)
end

# Helper to create temporary test files
def with_temp_public_dir(&)
  temp_dir = File.tempname("takarik_static_test")
  Dir.mkdir_p(temp_dir)

  begin
    yield temp_dir
  ensure
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end
end

describe Takarik::StaticFileHandler do
  describe "#call" do
    it "serves existing files" do
      with_temp_public_dir do |public_dir|
        # Create a test file
        test_file = File.join(public_dir, "test.txt")
        File.write(test_file, "Hello, World!")

        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
        context = create_static_test_context("GET", "/test.txt")

        result = handler.call(context)

        result.should be_true
        context.response.status.should eq(HTTP::Status::OK)
        context.response.headers["Content-Type"].should eq("text/plain")
        context.response.headers["Cache-Control"].should eq("public, max-age=3600")
        context.response.headers["ETag"]?.should_not be_nil
        context.response.headers["Last-Modified"]?.should_not be_nil
      end
    end

    it "returns false for non-existent files" do
      with_temp_public_dir do |public_dir|
        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
        context = create_static_test_context("GET", "/nonexistent.txt")

        result = handler.call(context)

        result.should be_false
      end
    end

    it "serves index files for directory requests" do
      with_temp_public_dir do |public_dir|
        # Create index file
        index_file = File.join(public_dir, "index.html")
        File.write(index_file, "<h1>Welcome</h1>")

        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
        context = create_static_test_context("GET", "/")

        result = handler.call(context)

        result.should be_true
        context.response.status.should eq(HTTP::Status::OK)
        context.response.headers["Content-Type"].should eq("text/html")
      end
    end

    it "prevents directory traversal attacks" do
      with_temp_public_dir do |public_dir|
        # Create a file outside the public directory
        parent_dir = File.dirname(public_dir)
        sensitive_file = File.join(parent_dir, "sensitive.txt")
        File.write(sensitive_file, "Secret data")

        begin
          handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
          context = create_static_test_context("GET", "/../sensitive.txt")

          result = handler.call(context)

          result.should be_false
        ensure
          File.delete(sensitive_file) if File.exists?(sensitive_file)
        end
      end
    end

    it "handles HEAD requests correctly" do
      with_temp_public_dir do |public_dir|
        test_file = File.join(public_dir, "test.txt")
        File.write(test_file, "Hello, World!")

        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
        context = create_static_test_context("HEAD", "/test.txt")

        result = handler.call(context)

        result.should be_true
        context.response.status.should eq(HTTP::Status::OK)
        context.response.headers["Content-Type"].should eq("text/plain")
        context.response.headers["Content-Length"].should eq("13")
        # Response body should be empty for HEAD requests
      end
    end

    it "returns false for non-GET/HEAD methods" do
      with_temp_public_dir do |public_dir|
        test_file = File.join(public_dir, "test.txt")
        File.write(test_file, "Hello, World!")

        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)

        ["POST", "PUT", "DELETE", "PATCH"].each do |method|
          context = create_static_test_context(method, "/test.txt")
          result = handler.call(context)
          result.should be_false
        end
      end
    end

    it "handles conditional requests with ETag" do
      with_temp_public_dir do |public_dir|
        test_file = File.join(public_dir, "test.txt")
        File.write(test_file, "Hello, World!")

        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)

        # First request to get ETag
        context1 = create_static_test_context("GET", "/test.txt")
        handler.call(context1)
        etag = context1.response.headers["ETag"]

        # Second request with If-None-Match
        headers = HTTP::Headers.new
        headers["If-None-Match"] = etag
        context2 = create_static_test_context("GET", "/test.txt", headers)

        result = handler.call(context2)

        result.should be_true
        context2.response.status.should eq(HTTP::Status::NOT_MODIFIED)
      end
    end

    it "sets correct MIME types" do
      with_temp_public_dir do |public_dir|
        files = {
          "style.css" => "text/css",
          "script.js" => "application/javascript",
          "image.png" => "image/png",
          "data.json" => "application/json"
        }

        files.each do |filename, expected_mime|
          file_path = File.join(public_dir, filename)
          File.write(file_path, "content")

          handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
          context = create_static_test_context("GET", "/#{filename}")

          handler.call(context)

          context.response.headers["Content-Type"].should eq(expected_mime)
        end
      end
    end

    it "handles URL decoding correctly" do
      with_temp_public_dir do |public_dir|
        # Create a file with spaces in the name
        test_file = File.join(public_dir, "test file.txt")
        File.write(test_file, "Hello, World!")

        handler = Takarik::StaticFileHandler.new(public_dir: public_dir)
        # Request with URL-encoded space
        context = create_static_test_context("GET", "/test%20file.txt")

        result = handler.call(context)

        result.should be_true
        context.response.status.should eq(HTTP::Status::OK)
      end
    end
  end

  describe ".static_path?" do
    it "returns true for root prefix" do
      Takarik::StaticFileHandler.static_path?("/anything", "/").should be_true
      Takarik::StaticFileHandler.static_path?("/assets/style.css", "/").should be_true
    end

    it "checks prefix correctly" do
      Takarik::StaticFileHandler.static_path?("/assets/style.css", "/assets").should be_true
      Takarik::StaticFileHandler.static_path?("/public/image.png", "/assets").should be_false
      Takarik::StaticFileHandler.static_path?("/api/users", "/assets").should be_false
    end
  end
end

describe Takarik::MimeTypes do
  describe ".mime_type_for" do
    it "returns correct MIME types for common files" do
      Takarik::MimeTypes.mime_type_for("style.css").should eq("text/css")
      Takarik::MimeTypes.mime_type_for("script.js").should eq("application/javascript")
      Takarik::MimeTypes.mime_type_for("image.png").should eq("image/png")
      Takarik::MimeTypes.mime_type_for("document.pdf").should eq("application/pdf")
    end

    it "returns default type for unknown extensions" do
      Takarik::MimeTypes.mime_type_for("unknown.xyz").should eq("application/octet-stream")
    end

    it "handles case insensitive extensions" do
      Takarik::MimeTypes.mime_type_for("IMAGE.PNG").should eq("image/png")
      Takarik::MimeTypes.mime_type_for("Style.CSS").should eq("text/css")
    end
  end

  describe ".text_mime_type?" do
    it "identifies text MIME types correctly" do
      Takarik::MimeTypes.text_mime_type?("text/plain").should be_true
      Takarik::MimeTypes.text_mime_type?("text/html").should be_true
      Takarik::MimeTypes.text_mime_type?("application/javascript").should be_true
      Takarik::MimeTypes.text_mime_type?("application/json").should be_true
      Takarik::MimeTypes.text_mime_type?("image/png").should be_false
      Takarik::MimeTypes.text_mime_type?("application/octet-stream").should be_false
    end
  end
end
