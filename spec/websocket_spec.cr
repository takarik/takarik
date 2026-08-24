require "./spec_helper"

private class TestSocket < Takarik::WebSocket
  getter received : Array(String)

  def initialize
    # A dummy IO-backed HTTP::WebSocket; never actually runs.
    super(HTTP::WebSocket.new(IO::Memory.new), {} of String => String)
    @received = [] of String
  end

  def initialize(@route_params : Hash(String, String))
    super(HTTP::WebSocket.new(IO::Memory.new), @route_params)
    @received = [] of String
  end

  def initialize(socket : ::HTTP::WebSocket, route_params : Hash(String, String))
    super(socket, route_params)
    @received = [] of String
  end

  def send(message : String)
    @received << message
  end

  def send(data : Bytes)
    @received << String.new(data)
  end

  def close(code = 1000, message = nil)
    @received << "__closed__"
  end

  def closed?
    false
  end
end

describe Takarik::WebSocket::Hub do
  it "tracks channel membership" do
    hub = Takarik::WebSocket::Hub.new
    socket_a = TestSocket.new
    socket_b = TestSocket.new

    hub.join("room:1", socket_a)
    hub.join("room:1", socket_b)
    hub.join("room:2", socket_a)

    hub.member_count("room:1").should eq(2)
    hub.member_count("room:2").should eq(1)
    hub.member_count("room:x").should eq(0)
    hub.channels.should contain("room:1")
    hub.channels.should contain("room:2")
  end

  it "broadcasts only to members of a channel" do
    hub = Takarik::WebSocket::Hub.new
    member = TestSocket.new
    other = TestSocket.new

    hub.join("room:1", member)
    hub.join("room:2", other)

    hub.broadcast("room:1", "hello")

    member.received.should eq(["hello"])
    other.received.empty?.should be_true
  end

  it "leaves channels cleanly and removes empty channels" do
    hub = Takarik::WebSocket::Hub.new
    socket = TestSocket.new
    hub.join("room:1", socket)
    hub.leave("room:1", socket)

    hub.member_count("room:1").should eq(0)
    hub.channels.empty?.should be_true

    # leaving twice is a no-op
    hub.leave("room:1", socket)
    hub.member_count("room:1").should eq(0)
  end

  it "removes a socket from all its channels at once" do
    hub = Takarik::WebSocket::Hub.new
    socket = TestSocket.new
    hub.join("a", socket)
    hub.join("b", socket)
    hub.join("c", TestSocket.new)

    hub.remove(socket)

    hub.member_count("a").should eq(0)
    hub.member_count("b").should eq(0)
    hub.member_count("c").should eq(1)
  end

  it "unicasts to a specific member of a channel" do
    hub = Takarik::WebSocket::Hub.new
    socket_a = TestSocket.new
    socket_b = TestSocket.new
    hub.join("room:1", socket_a)
    hub.join("room:1", socket_b)

    hub.unicast?("room:1", socket_b, "just you").should be_true

    socket_a.received.empty?.should be_true
    socket_b.received.should eq(["just you"])

    stranger = TestSocket.new
    hub.unicast?("room:1", stranger, "nope").should be_false
  end

  it "drops broken sockets encountered during broadcast" do
    hub = Takarik::WebSocket::Hub.new
    broken = BrokenSocket.new
    healthy = TestSocket.new

    hub.join("room:1", broken)
    hub.join("room:1", healthy)

    hub.broadcast("room:1", "hi")

    healthy.received.should eq(["hi"])
    hub.member_count("room:1").should eq(1)
  end
end

describe Takarik::Router do
  describe "#websocket" do
    it "matches a websocket path and extracts params" do
      router = Takarik::Router.instance
      router.websocket("/ws-test/:room", TestSocket)

      matched = router.match_websocket("/ws-test/lobby")
      matched.should_not be_nil
      socket_class, params = matched.not_nil!
      socket_class.should eq(TestSocket)
      params["room"].should eq("lobby")

      router.match_websocket("/ws-test/").should be_nil
      router.match_websocket("/nope").should be_nil
    end

    it "raises when a duplicate websocket route is defined" do
      router = Takarik::Router.instance
      expect_raises(Exception, /already defined/) do
        router.websocket("/ws-test/:room", TestSocket)
      end
    end
  end
end

private class BrokenSocket < TestSocket
  def send(message : String)
    raise IO::Error.new("dead pipe")
  end
end

describe Takarik::WebSocket, tags: "e2e" do
  it "upgrades connections and routes messages over TCP" do
    app_port = 3469
    router = Takarik::Router.instance
    router.websocket("/e2e/:room", E2ESocket)

    ws_handler = HTTP::WebSocketHandler.new do |socket, context|
      if matched = router.match_websocket(context.request.path.not_nil!)
        socket_class, params = matched
        socket_class.new(socket, params).__start__
      else
        context.response.status = :bad_request
      end
    end

    server = HTTP::Server.new([ws_handler]) { }
    address = server.bind_tcp("127.0.0.1", app_port)
    spawn { server.listen }

    begin
      client_a = HTTP::WebSocket.new("localhost", "/e2e/lobby", port: app_port)
      client_b = HTTP::WebSocket.new("localhost", "/e2e/lobby", port: app_port)

      messages_a = Channel(String).new
      messages_b = Channel(String).new

      client_a.on_message { |m| messages_a.send(m) }
      client_b.on_message { |m| messages_b.send(m) }

      spawn { client_a.run }
      spawn { client_b.run }

      # Both receive the welcome message with their room param
      messages_a.receive.should contain("welcome")
      messages_b.receive.should contain("welcome")

      # Broadcast reaches both clients
      client_a.send("hello everyone")
      msg_a = messages_a.receive
      msg_b = messages_b.receive
      msg_a.should eq("chat: hello everyone")
      msg_b.should eq("chat: hello everyone")

      # Member count reflects both connected clients
      client_a.send("count")
      count_msg = ""
      2.times do
        candidate = messages_a.receive
        break count_msg = candidate if candidate.starts_with?("members:")
      end
      count_msg.should eq("members: 2")
    ensure
      server.close
    end
  end
end

private class E2ESocket < Takarik::WebSocket
  def on_open
    join("e2e:#{route_params["room"]}")
    send("welcome to #{route_params["room"]}")
  end

  def on_message(message : String)
    case message
    when "count"
      send("members: #{hub.member_count("e2e:#{route_params["room"]}")}")
    else
      hub.broadcast("e2e:#{route_params["room"]}", "chat: #{message}")
    end
  end
end
