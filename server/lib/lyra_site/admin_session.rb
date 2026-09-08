# frozen_string_literal: true

require "openssl"
require "securerandom"
require "thread"

require_relative "password_hasher"

module LyraSite
  class AdminSession
    COOKIE = "lyra_admin_session"
    LOGIN_COOKIE = "lyra_login_csrf"
    MAX_AGE = 43_200
    LOGIN_WINDOW = 900
    MAX_FAILURES = 5

    attr_reader :username

    def initialize(secret:, username:, password:, clock: -> { Time.now.to_i })
      @secret, @username, @password, @clock = secret, username, password, clock
      @sessions = {}
      @failures = {}
      @mutex = Mutex.new
    end

    def enabled?
      !@password.to_s.empty?
    end

    def login_challenge
      payload = "#{@clock.call}.#{SecureRandom.hex(24)}"
      "#{payload}.#{OpenSSL::HMAC.hexdigest('SHA256', @secret, payload)}"
    end

    def valid_login_csrf?(request)
      cookie = cookie_value(request, LOGIN_COOKIE)
      submitted = request.query["csrf_token"].to_s
      return false unless PasswordHasher.secure_compare(cookie, submitted)

      timestamp, nonce, signature = cookie.split(".", 3)
      return false unless timestamp.to_s.match?(/\A\d+\z/) && nonce.to_s.match?(/\A[0-9a-f]{48}\z/)
      return false unless (0..LOGIN_WINDOW).cover?(@clock.call - timestamp.to_i)

      expected = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{nonce}")
      PasswordHasher.secure_compare(signature, expected)
    end

    def login(ip:, username:, password:)
      @mutex.synchronize do
        prune!
        failure = @failures[ip]
        return :limited if failure && failure[:count] >= MAX_FAILURES
        return :limited if !failure && @failures.length >= 10_000

        unless enabled? && PasswordHasher.secure_compare(username, @username) && PasswordHasher.secure_compare(password, @password)
          @failures[ip] ||= { count: 0, expires_at: @clock.call + LOGIN_WINDOW }
          @failures[ip][:count] += 1
          return :invalid
        end

        @failures.delete(ip)
        token = SecureRandom.hex(32)
        @sessions.shift if @sessions.length >= 1000
        @sessions[digest(token)] = { csrf: SecureRandom.hex(32), expires_at: @clock.call + MAX_AGE }
        token
      end
    end

    def find(request)
      @mutex.synchronize do
        prune!
        @sessions[digest(cookie_value(request, COOKIE))]&.dup
      end
    end

    def valid_csrf?(session, value)
      session && PasswordHasher.secure_compare(session.fetch(:csrf), value.to_s)
    end

    def logout(request)
      @mutex.synchronize { @sessions.delete(digest(cookie_value(request, COOKIE))) }
    end

    private

    def cookie_value(request, name)
      request.cookies.find { |cookie| cookie.name == name }&.value.to_s
    end

    def digest(value)
      OpenSSL::Digest::SHA256.hexdigest(value)
    end

    def prune!
      now = @clock.call
      @sessions.delete_if { |_, session| session[:expires_at] <= now }
      @failures.delete_if { |_, failure| failure[:expires_at] <= now }
    end
  end
end
