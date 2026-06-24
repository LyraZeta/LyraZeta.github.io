# frozen_string_literal: true

require "base64"
require "openssl"
require "securerandom"

module LyraSite
  class PasswordHasher
    ALGORITHM = "pbkdf2_sha256"
    ITERATIONS = 120_000
    KEY_LENGTH = 32

    def self.hash(password)
      salt = SecureRandom.hex(16)
      digest = OpenSSL::PKCS5.pbkdf2_hmac(
        password.to_s,
        salt,
        ITERATIONS,
        KEY_LENGTH,
        OpenSSL::Digest::SHA256.new
      )

      [ALGORITHM, ITERATIONS, salt, Base64.strict_encode64(digest)].join("$")
    end

    def self.verify?(password, encoded_hash)
      algorithm, iterations, salt, expected_digest = encoded_hash.to_s.split("$", 4)
      return false unless algorithm == ALGORITHM
      return false if iterations.to_s.empty? || salt.to_s.empty? || expected_digest.to_s.empty?

      digest = OpenSSL::PKCS5.pbkdf2_hmac(
        password.to_s,
        salt,
        Integer(iterations, 10),
        KEY_LENGTH,
        OpenSSL::Digest::SHA256.new
      )

      secure_compare(Base64.strict_encode64(digest), expected_digest)
    rescue ArgumentError
      false
    end

    def self.secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end
  end
end
