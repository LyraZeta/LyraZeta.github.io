# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../server/lib/lyra_site/password_hasher"

class PasswordHasherTest < Minitest::Test
  def test_hash_and_verify
    encoded = LyraSite::PasswordHasher.hash("secret")

    assert LyraSite::PasswordHasher.verify?("secret", encoded)
    refute LyraSite::PasswordHasher.verify?("wrong", encoded)
  end

  def test_invalid_hash_returns_false
    refute LyraSite::PasswordHasher.verify?("secret", "bad")
  end
end
