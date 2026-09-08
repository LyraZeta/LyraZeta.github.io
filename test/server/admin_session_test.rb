# frozen_string_literal: true

require "minitest/autorun"
require "webrick"
require_relative "../../server/lib/lyra_site/admin_session"

class AdminSessionTest < Minitest::Test
  Request = Struct.new(:cookies, :query)

  def setup
    @time = 1_800_000_000
    @sessions = LyraSite::AdminSession.new(secret: "test-secret", username: "admin", password: "test-password", clock: -> { @time })
  end

  def login(password = "test-password", ip = "203.0.113.2")
    @sessions.login(ip: ip, username: "admin", password: password)
  end

  def request(token, name = LyraSite::AdminSession::COOKIE, query = {})
    Request.new([WEBrick::Cookie.new(name, token)], query)
  end

  def test_sessions_are_random_expire_server_side_and_logout_revokes_token
    token = login
    refute_equal token, login
    req = request(token)
    session = @sessions.find(req)
    assert @sessions.valid_csrf?(session, session[:csrf])
    refute @sessions.valid_csrf?(session, "forged")
    @sessions.logout(req)
    assert_nil @sessions.find(req)
    req = request(login)
    @time += LyraSite::AdminSession::MAX_AGE
    assert_nil @sessions.find(req)
  end

  def test_login_throttling_expires_and_is_ip_scoped
    5.times { assert_equal :invalid, login("incorrect") }
    assert_equal :limited, login
    assert_kind_of String, login("test-password", "203.0.113.3")
    @time += 900
    assert_kind_of String, login
  end

  def test_login_csrf_needs_valid_signature_cookie_and_expiry
    challenge = @sessions.login_challenge
    req = request(challenge, LyraSite::AdminSession::LOGIN_COOKIE, "csrf_token" => challenge)
    assert @sessions.valid_login_csrf?(req)
    req.query["csrf_token"] = "forged"
    refute @sessions.valid_login_csrf?(req)
    req.query["csrf_token"] = challenge
    @time += 901
    refute @sessions.valid_login_csrf?(req)
    refute @sessions.valid_login_csrf?(Request.new([], {}))
  end
end
