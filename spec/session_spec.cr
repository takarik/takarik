require "./spec_helper"
require "../src/takarik/session/*"

describe "Session Management" do
  describe "Session Stores" do
    describe "MemoryStore" do
      it "can store and retrieve session data" do
        store = Takarik::Session::MemoryStore.new
        session_id = store.generate_session_id
        data = {"user_id" => JSON::Any.new("123"), "name" => JSON::Any.new("John")}

        store.write(session_id, data).should be_true
        retrieved = store.read(session_id)
        retrieved.should_not be_nil
        retrieved.not_nil!["user_id"].as_s.should eq("123")
        retrieved.not_nil!["name"].as_s.should eq("John")
      end

      it "returns nil for non-existent sessions" do
        store = Takarik::Session::MemoryStore.new
        store.read("nonexistent").should be_nil
      end

      it "can delete sessions" do
        store = Takarik::Session::MemoryStore.new
        session_id = store.generate_session_id
        data = {"test" => JSON::Any.new("value")}

        store.write(session_id, data)
        store.exists?(session_id).should be_true
        store.delete(session_id).should be_true
        store.exists?(session_id).should be_false
      end

      it "cleans up expired sessions" do
        store = Takarik::Session::MemoryStore.new(max_age: 1.millisecond)
        session_id = store.generate_session_id
        data = {"test" => JSON::Any.new("value")}

        store.write(session_id, data)
        store.exists?(session_id).should be_true

        sleep 2.milliseconds
        store.exists?(session_id).should be_false
      end
    end

    describe "CookieStore" do
      it "can encrypt and decrypt session data" do
        store = Takarik::Session::CookieStore.new("secret_key_for_testing")
        data = {"user_id" => JSON::Any.new("456"), "role" => JSON::Any.new("admin")}

        encrypted = store.encrypt_session_data(data)
        encrypted.should_not be_empty

        decrypted = store.decrypt_session_data(encrypted)
        decrypted.should_not be_nil
        decrypted.not_nil!["user_id"].as_s.should eq("456")
        decrypted.not_nil!["role"].as_s.should eq("admin")
      end

      it "returns nil for invalid encrypted data" do
        store = Takarik::Session::CookieStore.new("secret_key_for_testing")
        store.decrypt_session_data("invalid_data").should be_nil
        store.decrypt_session_data("").should be_nil
      end

      it "can get encrypted data for cookies" do
        store = Takarik::Session::CookieStore.new("secret_key_for_testing")
        data = {"test" => JSON::Any.new("value")}

        encrypted = store.get_encrypted_data(data)
        encrypted.should_not be_nil
        encrypted.not_nil!.should_not be_empty
      end

      it "respects max size limits" do
        store = Takarik::Session::CookieStore.new("secret_key_for_testing", max_size: 10)
        large_data = {"large_value" => JSON::Any.new("x" * 1000)}

        encrypted = store.get_encrypted_data(large_data)
        encrypted.should be_nil  # Should be nil because it exceeds max_size
      end
    end
  end

  describe "Session API" do
    it "can store and retrieve values" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session["user_id"] = "123"
      session["name"] = "Alice"

      session["user_id"].should_not be_nil
      session["user_id"].not_nil!.as_s.should eq("123")
      session["name"].not_nil!.as_s.should eq("Alice")
    end

    it "returns nil for non-existent keys" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session["nonexistent"].should be_nil
    end

    it "can delete values" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session["test"] = "value"
      session.has_key?("test").should be_true

      session.delete("test")
      session.has_key?("test").should be_false
    end

    it "tracks dirty state correctly" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session.dirty?.should be_false
      session["key"] = "value"
      session.dirty?.should be_true

      session.save
      session.dirty?.should be_false
    end

    it "can clear all data" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session["key1"] = "value1"
      session["key2"] = "value2"
      session.empty?.should be_false

      session.clear
      session.empty?.should be_true
      session.dirty?.should be_true
    end

    it "can destroy session completely" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session["test"] = "value"
      session.save
      store.exists?(session.id).should be_true

      session.destroy
      store.exists?(session.id).should be_false
    end

    it "converts various types to JSON::Any" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)

      session["string"] = "hello"
      session["int"] = 42
      session["float"] = 3.14
      session["bool"] = true
      session["array"] = [1, 2, 3]
      session["hash"] = {"nested" => "value"}

      session["string"].not_nil!.as_s.should eq("hello")
      session["int"].not_nil!.as_i64.should eq(42)
      session["float"].not_nil!.as_f.should eq(3.14)
      session["bool"].not_nil!.as_bool.should be_true
      session["array"].not_nil!.as_a.size.should eq(3)
      session["hash"].not_nil!.as_h["nested"].as_s.should eq("value")
    end
  end

  describe "Flash Messages" do
    it "can set and get flash messages" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)
      flash = session.flash

      flash["notice"] = "Success message"
      flash["alert"] = "Warning message"

      flash["notice"].not_nil!.as_s.should eq("Success message")
      flash["alert"].not_nil!.as_s.should eq("Warning message")
    end

    it "provides convenience methods for common flash types" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)
      flash = session.flash

      flash.notice = "Success!"
      flash.alert = "Warning!"
      flash.error = "Error!"

      flash.notice.should eq("Success!")
      flash.alert.should eq("Warning!")
      flash.error.should eq("Error!")
    end

    it "can check if flash is empty" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)
      flash = session.flash

      flash.empty?.should be_true
      flash["test"] = "value"
      flash.empty?.should be_false
    end

    it "can clear flash messages" do
      store = Takarik::Session::MemoryStore.new
      session = Takarik::Session::Instance.new(store)
      flash = session.flash

      flash["test"] = "value"
      flash.empty?.should be_false
      flash.clear
      flash.empty?.should be_true
    end

    it "persists flash messages through session save/load" do
      store = Takarik::Session::MemoryStore.new
      session1 = Takarik::Session::Instance.new(store, "test_session")

      # Set flash in first session
      session1.flash["notice"] = "Hello from flash!"
      session1.save

      # Load session again (simulating new request)
      session2 = Takarik::Session::Instance.new(store, "test_session")
      session2.load

      # Flash should be available but moved to regular flash
      flash = session2.flash
      flash["notice"].not_nil!.as_s.should eq("Hello from flash!")
    end
  end

  describe "Session Configuration" do
    it "can configure memory sessions" do
      config = Takarik::Configuration.new
      config.use_memory_sessions(max_age: 2.hours)

      config.sessions_enabled?.should be_true
      config.session_store.should be_a(Takarik::Session::MemoryStore)
    end

    it "can configure cookie sessions" do
      config = Takarik::Configuration.new
      config.use_cookie_sessions("secret_key", max_size: 2048)

      config.sessions_enabled?.should be_true
      config.session_store.should be_a(Takarik::Session::CookieStore)
    end

    it "can disable sessions" do
      config = Takarik::Configuration.new
      config.sessions_enabled?.should be_true  # Default enabled

      config.disable_sessions!
      config.sessions_enabled?.should be_false
    end

    it "can configure session options" do
      config = Takarik::Configuration.new
      config.sessions(
        cookie_name: "my_session",
        secure: true,
        http_only: false,
        same_site: "Strict"
      )

      config.session_cookie_name.should eq("my_session")
      config.session_cookie_secure.should be_true
      config.session_cookie_http_only.should be_false
      config.session_cookie_same_site.should eq("Strict")
    end
  end
end
