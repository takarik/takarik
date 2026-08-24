require "./spec_helper"

private class GuardSocket < Takarik::WebSocket
  def on_open
    send("connected")
  end

  def on_message(message : String)
    send("echo: #{message}")
  end
end

private def guard_server(app : Takarik::Application)
  server = HTTP::Server.new([app.websocket_handler]) { }
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  {server, address.port}
end

describe "WebSocket upgrade guards", tags: "e2e" do
  it "accepts upgrades when no guards are configured" do
    router = Takarik::Router.instance
    router.websocket("/guard/open", GuardSocket)
    app = Takarik::Application.new(port: 0)

    server, port = guard_server(app)
    begin
      client = HTTP::WebSocket.new("localhost", "/guard/open", port: port)
      messages = Channel(String).new
      client.on_message { |m| messages.send(m) }
      spawn { client.run }

      messages.receive.should eq("connected")
      client.close
    ensure
      server.close
    end
  end

  it "rejects disallowed origins with 403" do
    router = Takarik::Router.instance
    router.websocket("/guard/origin", GuardSocket)
    Takarik.config.websocket_origins(["https://good.example.com"])

    app = Takarik::Application.new(port: 0)
    server, port = guard_server(app)
    begin
      # Disallowed origin -> handshake rejected
      expect_raises(Exception, /403|Forbidden/) do
        HTTP::WebSocket.new("localhost", "/guard/origin",
          headers: HTTP::Headers{"Origin" => "https://evil.example.com"}, port: port).run
      end
    ensure
      server.close
      Takarik.config.websocket_origins(nil)
    end
  end

  it "accepts allowed origins (case-insensitive)" do
    router = Takarik::Router.instance
    router.websocket("/guard/origin-ok", GuardSocket)
    Takarik.config.websocket_origins(["HTTPS://Good.Example.COM"])

    app = Takarik::Application.new(port: 0)
    server, port = guard_server(app)
    begin
      client = HTTP::WebSocket.new("localhost", "/guard/origin-ok",
        headers: HTTP::Headers{"Origin" => "https://good.example.com"}, port: port)
      messages = Channel(String).new
      client.on_message { |m| messages.send(m) }
      spawn { client.run }

      messages.receive.should eq("connected")
      client.close
    ensure
      server.close
      Takarik.config.websocket_origins(nil)
    end
  end

  it "supports a before_upgrade auth hook" do
    router = Takarik::Router.instance
    router.websocket("/guard/auth", GuardSocket)

    app = Takarik::Application.new(port: 0)
    app.on_websocket_upgrade do |context|
      # Simulate token auth via query string or header
      context.request.headers["Authorization"]? == "secret-token"
    end

    server, port = guard_server(app)
    begin
      # Missing token -> rejected
      expect_raises(Exception) do
        HTTP::WebSocket.new("localhost", "/guard/auth", port: port).run
      end

      # Valid token -> accepted
      authorized = HTTP::WebSocket.new("localhost", "/guard/auth",
        headers: HTTP::Headers{"Authorization" => "secret-token"}, port: port)
      messages = Channel(String).new
      authorized.on_message { |m| messages.send(m) }
      spawn { authorized.run }

      messages.receive.should eq("connected")
      authorized.close
    ensure
      server.close
    end
  end

  it "treats a raising before_upgrade hook as a rejection" do
    router = Takarik::Router.instance
    router.websocket("/guard/crashy", GuardSocket)

    app = Takarik::Application.new(port: 0)
    app.on_websocket_upgrade do |_context|
      raise "boom"
    end

    server, port = guard_server(app)
    begin
      expect_raises(Exception) do
        HTTP::WebSocket.new("localhost", "/guard/crashy", port: port).run
      end
    ensure
      server.close
    end
  end
end
