# frozen_string_literal: true

require "openssl"

require_relative "password_hasher"
require_relative "protection_store"

module LyraSite
  class AccessSession
    MAX_AGE = 60 * 60 * 24 * 30

    def initialize(secret:)
      @secret = secret.to_s
    end

    def authorized?(request, url, version:)
      canonical = ProtectionStore.canonical_url(url)
      cookie = request.cookies.find { |item| item.name == cookie_name(canonical) }
      return false unless cookie

      PasswordHasher.secure_compare(cookie.value, token_for(canonical, version))
    end

    def grant(response, url, version:, secure: false)
      canonical = ProtectionStore.canonical_url(url)
      cookie = [
        "#{cookie_name(canonical)}=#{token_for(canonical, version)}",
        "Path=/",
        "Max-Age=#{MAX_AGE}",
        "HttpOnly",
        "SameSite=Lax"
      ].join("; ")

      cookie += "; Secure" if secure
      response["Set-Cookie"] = cookie
    end

    private

    def cookie_name(url)
      digest = OpenSSL::Digest::SHA256.hexdigest(url)[0, 24]
      "lyra_post_#{digest}"
    end

    def token_for(url, version)
      OpenSSL::HMAC.hexdigest("SHA256", @secret, "post-access:#{url}:#{version}")
    end
  end
end
