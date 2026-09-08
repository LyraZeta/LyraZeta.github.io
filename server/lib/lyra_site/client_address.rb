# frozen_string_literal: true

require "ipaddr"

module LyraSite
  class ClientAddress
    def initialize(trusted_proxies: "127.0.0.1/32,::1/128")
      @networks = trusted_proxies.split(",").map(&:strip).reject(&:empty?).map { |cidr| IPAddr.new(cidr) }
    end

    def ip(request)
      peer = normalize(request.peeraddr[3])
      return peer unless trusted?(peer)

      forwarded = request["X-Forwarded-For"].to_s
      return peer if forwarded.empty? || forwarded.bytesize > 2048

      chain = forwarded.split(",").map { |address| normalize(address.strip) }
      return peer if chain.length > 32 || chain.include?(nil)

      # Walk from the socket peer toward the client, stopping at the first untrusted hop.
      (chain + [peer]).reverse.find { |address| !trusted?(address) } || chain.first || peer
    end

    def secure?(request)
      # This backend listens on HTTP. WEBrick's ssl? also trusts forwarded headers.
      trusted?(request.peeraddr[3]) && request["X-Forwarded-Proto"] == "https"
    end

    private

    def normalize(value)
      return nil if value.to_s.include?("/")

      address = IPAddr.new(value.to_s)
      (address.ipv4_mapped? ? address.native : address).to_s
    rescue IPAddr::InvalidAddressError
      nil
    end

    def trusted?(value)
      address = IPAddr.new(value.to_s)
      @networks.any? { |network| network.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
