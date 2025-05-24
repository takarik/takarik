require "./store"
require "base64"
require "json"
require "openssl/cipher"
require "digest/sha256"

module Takarik
  module Session
    # Cookie-based session store that encrypts session data
    class CookieStore < Store
      @secret_key : Bytes
      @cipher_name : String
      @max_size : Int32

      def initialize(secret_key : String, @cipher_name = "AES-256-CBC", @max_size = 4096)
        # Derive a proper key from the secret
        @secret_key = Digest::SHA256.digest(secret_key)[0, 32]
      end

      def read(session_id : String) : Hash(String, JSON::Any)?
        # For cookie store, session_id is actually the encrypted data
        decrypt_session_data(session_id)
      end

      def write(session_id : String, data : Hash(String, JSON::Any)) : Bool
        # We don't use session_id for cookie store, data is the important part
        encrypted = encrypt_session_data(data)
        encrypted.bytesize <= @max_size
      end

      def delete(session_id : String) : Bool
        # For cookie store, deletion is handled by the cookie expiration
        true
      end

      def exists?(session_id : String) : Bool
        read(session_id) != nil
      end

      def cleanup : Int32
        # Cookie store doesn't need cleanup - cookies expire on their own
        0
      end

      # Encrypt session data for cookie storage
      def encrypt_session_data(data : Hash(String, JSON::Any)) : String
        json_data = data.to_json

        cipher = OpenSSL::Cipher.new(@cipher_name)
        cipher.encrypt
        cipher.key = @secret_key

        # Generate random IV
        iv = Random::Secure.random_bytes(cipher.iv_len)
        cipher.iv = iv

        encrypted = cipher.update(json_data.to_slice)
        encrypted += cipher.final

        # Combine IV + encrypted data and encode
        combined = iv + encrypted
        Base64.strict_encode(combined)
      end

      # Decrypt session data from cookie
      def decrypt_session_data(encrypted_data : String) : Hash(String, JSON::Any)?
        return nil if encrypted_data.empty?

        combined = Base64.decode(encrypted_data)

        cipher = OpenSSL::Cipher.new(@cipher_name)
        cipher.decrypt
        cipher.key = @secret_key

        # Extract IV and encrypted data
        iv_len = cipher.iv_len
        return nil if combined.size <= iv_len

        iv = combined[0, iv_len]
        encrypted = combined[iv_len..-1]

        cipher.iv = iv

        decrypted = cipher.update(encrypted)
        decrypted += cipher.final

        json_str = String.new(decrypted)
        parsed = JSON.parse(json_str)

        if parsed.as_h?
          result = {} of String => JSON::Any
          parsed.as_h.each { |k, v| result[k.to_s] = v }
          result
        else
          nil
        end
      rescue Base64::Error | OpenSSL::Error | JSON::ParseException
        nil
      end

      # Get encrypted session data for setting in cookie
      def get_encrypted_data(data : Hash(String, JSON::Any)) : String?
        return nil if data.empty?
        encrypted = encrypt_session_data(data)
        encrypted.bytesize <= @max_size ? encrypted : nil
      rescue
        nil
      end
    end
  end
end
