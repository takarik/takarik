require "./spec_helper"

# --- Test model & serializers -----------------------------------------------

private class SpecUser
  include Takarik::Resource
  include ::JSON::Serializable

  property id : Int64?
  property name : String
  property email : String?
  property age : Int32?
  property active : Bool

  def initialize(@name = "", @email = nil, @age = nil, @active = false, @id = nil)
  end
end

private class UserSerializer < Takarik::Serializer(SpecUser)
  def serialize : ::JSON::Any
    ::JSON::Any.new({
      "id"    => ::JSON::Any.new(object.id.try(&.to_s) || ""),
      "name"  => ::JSON::Any.new(object.name),
      "email" => object.email ? ::JSON::Any.new(object.email.not_nil!) : ::JSON::Any.new(nil),
      "age"   => object.age ? ::JSON::Any.new(object.age.not_nil!.to_i64) : ::JSON::Any.new(nil),
    })
  end
end

private class ApiUserSerializer < Takarik::JSONAPI::Serializer(SpecUser)
  def attributes : Hash(String, ::JSON::Any)
    {
      "name"   => ::JSON::Any.new(object.name),
      "email"  => object.email ? ::JSON::Any.new(object.email.not_nil!) : ::JSON::Any.new(nil),
      "active" => ::JSON::Any.new(object.active),
    }
  end
end

# Serializers register themselves automatically via the `inherited` hook on
# Takarik::Serializer — no manual `register` call needed.

# Explicit re-registration still works and overrides the auto-registered entry:
class RenamedUserSerializer < UserSerializer; end
Takarik::Serializers.register(RenamedUserSerializer)

# --- Unit tests ---------------------------------------------------------------

describe "Takarik::Serializer" do
  it "registers serializers automatically via the inherited hook" do
    entry = Takarik::Serializers.entry_for(SpecUser)
    entry.should_not be_nil
    entry.not_nil!.name.should eq("RenamedUserSerializer")
    Takarik::Serializers.entry_api_for(SpecUser).should_not be_nil
  end

  it "serializes to plain JSON" do
    doc = UserSerializer.new(SpecUser.new(name: "Alice", id: 1_i64)).serialize
    doc.as_h["name"].as_s.should eq("Alice")
  end

  it "derives JSON-API type from the class name" do
    Takarik::JSONAPI.type_for(SpecUser).should eq("spec_users")
    Takarik::JSONAPI.type_for(String).should eq("strings")
    # naive pluralization edge cases
    Takarik::JSONAPI.type_for(Struct).should eq("structs")
  end

  it "builds a JSON-API resource object from a plain serializer" do
    obj = UserSerializer.new(SpecUser.new(name: "Bob", id: 7_i64)).resource_object
    obj["type"].as_s.should eq("spec_users")
    obj["id"].as_s.should eq("7")
    obj["attributes"].as_h["name"].as_s.should eq("Bob")
  end

  it "deserializes a flat payload by default" do
    payload = ::JSON.parse(%({"name": "Carol", "age": 30}))
    UserSerializer.deserialize(payload)["name"].as_s.should eq("Carol")
  end
end

describe "Takarik::JSONAPI::Serializer" do
  it "wraps output in a compliant document" do
    doc = ApiUserSerializer.new(SpecUser.new(name: "Dan", id: 3_i64, active: true)).to_json_api
    data = doc.as_h["data"].as_h
    data["type"].as_s.should eq("spec_users")
    data["id"].as_s.should eq("3")
    data["attributes"].as_h["active"].as_bool.should be_true
  end

  it "digs into data.attributes for deserialization" do
    payload = ::JSON.parse(%({"data": {"type": "users", "id": "9", "attributes": {"name": "Eve", "active": true}}}))
    attrs = ApiUserSerializer.deserialize(payload)
    attrs["name"].as_s.should eq("Eve")
    ApiUserSerializer.deserialize_id(payload).should eq("9")
  end

  it "raises on malformed payloads" do
    expect_raises(ArgumentError) do
      ApiUserSerializer.deserialize(::JSON.parse(%({"name": "no envelope"})))
    end
  end
end

# --- Controller integration ---------------------------------------------------

private class SerializerTestController < Takarik::BaseController
  actions :show_auto_json, :show_explicit_json, :show_jsonapi, :show_jsonapi_explicit,
    :show_jsonapi_explicit_unregistered_flavor, :show_jsonapi_named,
    :index_jsonapi, :index_jsonapi_explicit, :create_from_payload

  def show_auto_json
    render json: SpecUser.new(name: "Alice", id: 1_i64)
  end

  def show_explicit_json
    render json: SpecUser.new(name: "Alice", id: 1_i64), serializer: UserSerializer
  end

  def show_jsonapi
    render jsonapi: SpecUser.new(name: "Dan", id: 3_i64, active: true)
  end

  def show_jsonapi_explicit
    # Class-based explicit serializer: dispatched directly via __takarik_entry,
    # ignoring whatever JSON-API serializer is registered for SpecUser.
    render jsonapi: SpecUser.new(name: "Erin", id: 4_i64, active: true), serializer: ApiUserSerializer
  end

  def show_jsonapi_explicit_unregistered_flavor
    # Even though Api::UserSerializer-like JSON-API serializers are registered
    # for this model, passing the plain serializer class must use IT:
    # its to_json_api produces a bare resource object (no "data" envelope).
    render jsonapi: SpecUser.new(name: "Finn", id: 5_i64), serializer: UserSerializer
  end

  def show_jsonapi_named
    # String form: looked up among registered serializers by class name.
    render jsonapi: SpecUser.new(name: "Gus", id: 6_i64), serializer: "ApiUserSerializer"
  end

  def index_jsonapi
    render jsonapi: [SpecUser.new(name: "A", id: 1_i64), SpecUser.new(name: "B", id: 2_i64)]
  end

  def index_jsonapi_explicit
    render jsonapi: [SpecUser.new(name: "X", id: 8_i64)], serializer: ApiUserSerializer
  end

  def create_from_payload
    # In a real app, takarik-data (ORM) would own attribute assignment;
    # here we apply the deserialized attributes manually.
    attrs = resource_attributes(SpecUser)
    user = SpecUser.new
    user.name = attrs["name"].as_s if attrs.has_key?("name")
    user.age = attrs["age"]?.try(&.as_i64?.try(&.to_i32))
    render json: user
  end
end

# --- Test harness -------------------------------------------------------------

private record Resp, body : String, content_type : String?

private def dispatch_to_controller(controller_class, method = "GET", path = "/", body = nil)
  headers = HTTP::Headers.new
  headers["Content-Type"] = "application/json" if body
  body_io = IO::Memory.new
  body_io.print(body) if body
  body_io.rewind

  request = HTTP::Request.new(method, path, headers, body_io)
  response_io = IO::Memory.new
  response = HTTP::Server::Response.new(response_io)
  context = HTTP::Server::Context.new(request, response)

  instance = controller_class.new(context, {} of String => String)
  yield instance
  context.response.close unless context.response.closed?
  response_io.rewind
  raw = response_io.gets_to_end
  body = raw.includes?("\r\n\r\n") ? raw.split("\r\n\r\n", 2)[1] : raw
  Resp.new(body: body, content_type: response.headers["Content-Type"]?)
end

describe "Controllers: serializer rendering & deserialization" do
  it "auto-finds registered serializers for render json:" do
    body = dispatch_to_controller(SerializerTestController) { |c| c.show_auto_json }.body
    parsed = ::JSON.parse(body)
    parsed["name"].as_s.should eq("Alice")
  end

  it "accepts an explicit serializer" do
    body = dispatch_to_controller(SerializerTestController) { |c| c.show_explicit_json }.body
    parsed = ::JSON.parse(body)
    parsed["name"].as_s.should eq("Alice")
  end

  it "renders JSON-API documents with content type vnd.api+json" do
    resp = dispatch_to_controller(SerializerTestController) { |c| c.show_jsonapi }
    resp.content_type.should eq("application/vnd.api+json")
    parsed = ::JSON.parse(resp.body)
    parsed["data"]["type"].as_s.should eq("spec_users")
    parsed["data"]["attributes"]["name"].as_s.should eq("Dan")
  end

  it "renders JSON-API with an explicit serializer (typed overload, no registry lookup)" do
    resp = dispatch_to_controller(SerializerTestController) { |c| c.show_jsonapi_explicit }
    resp.content_type.should eq("application/vnd.api+json")
    parsed = ::JSON.parse(resp.body)
    parsed["data"]["type"].as_s.should eq("spec_users")
    parsed["data"]["id"].as_s.should eq("4")
    parsed["data"]["attributes"]["name"].as_s.should eq("Erin")
  end

  it "renders collections as a JSON-API array" do
    resp = dispatch_to_controller(SerializerTestController) { |c| c.index_jsonapi }
    parsed = ::JSON.parse(resp.body)
    docs = parsed["data"].as_a
    docs.size.should eq(2)
    docs[0]["attributes"]["name"].as_s.should eq("A")
  end

  it "renders collections with an explicit serializer (typed overload)" do
    resp = dispatch_to_controller(SerializerTestController) { |c| c.index_jsonapi_explicit }
    resp.content_type.should eq("application/vnd.api+json")
    parsed = ::JSON.parse(resp.body)
    docs = parsed["data"].as_a
    docs.size.should eq(1)
    docs[0]["id"].as_s.should eq("8")
    docs[0]["attributes"]["name"].as_s.should eq("X")
  end

  it "uses the passed class verbatim, not the registered JSON-API serializer" do
    resp = dispatch_to_controller(SerializerTestController) { |c| c.show_jsonapi_explicit_unregistered_flavor }
    parsed = ::JSON.parse(resp.body)
    # UserSerializer is a plain serializer: bare resource object, no envelope
    parsed["type"].as_s.should eq("spec_users")
    parsed["attributes"]["name"].as_s.should eq("Finn")
    parsed.as_h.has_key?("data").should be_false
  end

  it "still supports lookup by registered serializer name" do
    resp = dispatch_to_controller(SerializerTestController) { |c| c.show_jsonapi_named }
    parsed = ::JSON.parse(resp.body)
    parsed["data"]["attributes"]["name"].as_s.should eq("Gus")
  end

  it "deserializes a flat JSON payload onto model setters" do
    resp = dispatch_to_controller(SerializerTestController, method: "POST",
      body: %({"name": "Frank", "age": 41, "active": true})) { |c| c.create_from_payload }

    parsed = ::JSON.parse(resp.body)
    parsed["name"].as_s.should eq("Frank")
    parsed["age"].as_i.should eq(41)
  end

  it "deserializes a JSON-API payload via the registered JSON-API serializer" do
    resp = dispatch_to_controller(SerializerTestController, method: "POST",
      body: %({"data": {"type": "spec_users", "attributes": {"name": "Gina", "active": true}}})) { |c| c.create_from_payload }

    parsed = ::JSON.parse(resp.body)
    parsed["name"].as_s.should eq("Gina")
  end
end
