# frozen_string_literal: true

require "minitest/autorun"
require "uri"
require_relative "../../server/lib/lyra_site/client_address"

class ClientAddressTest < Minitest::Test
  Request = Struct.new(:peeraddr, :request_uri, :headers) do
    def [](key)
      headers[key]
    end
  end

  def request(peer, forwarded = nil, proto = nil)
    Request.new(["AF_INET", 1234, peer, peer], URI("http://example.test/"), { "X-Forwarded-For" => forwarded, "X-Forwarded-Proto" => proto })
  end

  def test_direct_clients_cannot_spoof_ip_or_tls
    resolver = LyraSite::ClientAddress.new
    req = request("203.0.113.2", "1.2.3.4", "https")
    req.request_uri = URI("https://example.test/")
    assert_equal "203.0.113.2", resolver.ip(req)
    refute resolver.secure?(req)
  end

  def test_trusted_proxy_ignores_forged_leftmost_hop
    resolver = LyraSite::ClientAddress.new
    req = request("127.0.0.1", "1.2.3.4, 203.0.113.2", "https")
    assert_equal "203.0.113.2", resolver.ip(req)
    assert resolver.secure?(req)
  end

  def test_ipv6_custom_chains_and_invalid_headers
    resolver = LyraSite::ClientAddress.new(trusted_proxies: "127.0.0.1/32,10.0.0.0/8")
    assert_equal "2001:db8::2", resolver.ip(request("127.0.0.1", "2001:db8::2, 10.0.1.1"))
    assert_equal "127.0.0.1", resolver.ip(request("127.0.0.1", "bad, 203.0.113.2"))
    assert_equal "127.0.0.1", resolver.ip(request("127.0.0.1", "203.0.113.2/24"))
    assert_equal "203.0.113.2", resolver.ip(request("::ffff:203.0.113.2"))
    assert_raises(IPAddr::InvalidAddressError) { LyraSite::ClientAddress.new(trusted_proxies: "invalid") }
  end

end
