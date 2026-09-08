# frozen_string_literal: true

require "ipaddr"

module LyraSite
  class ClientAddress
    def self.normalize_ip(value)
      text = value.to_s
      return nil unless text.bytesize <= 45 && text.match?(/\A[0-9a-fA-F:.]+\z/)

      address = IPAddr.new(text)
      (address.ipv4_mapped? ? address.native : address).to_s
    rescue IPAddr::InvalidAddressError
      nil
    end

    def initialize(trusted_proxies: "127.0.0.1/32,::1/128")
      @networks = trusted_proxies.split(",").map(&:strip).reject(&:empty?).map { |cidr| IPAddr.new(cidr) }
    end

    def ip(request)
      peer = self.class.normalize_ip(request.peeraddr[3])
      return peer unless trusted?(peer)

      chain = forwarded_chain(request)
      return peer unless chain

      # Walk from the socket peer toward the client, stopping at the first untrusted hop.
      (chain + [peer]).reverse.find { |address| !trusted?(address) } || chain.first || peer
    end

    def visitor_ip(request)
      peer = self.class.normalize_ip(request.peeraddr[3])
      return peer unless trusted?(peer)

      # Proxy fallback addresses are useful for logs, never for granting access.
      forwarded_chain(request)&.reverse&.find { |address| !trusted?(address) }
    end

    def secure?(request)
      # This backend listens on HTTP. WEBrick's ssl? also trusts forwarded headers.
      trusted?(request.peeraddr[3]) && request["X-Forwarded-Proto"] == "https"
    end

    private

    def forwarded_chain(request)
      forwarded = request["X-Forwarded-For"].to_s
      return nil if forwarded.empty? || forwarded.bytesize > 2048

      chain = forwarded.split(",", -1).map { |address| self.class.normalize_ip(address.strip) }
      chain if chain.length <= 32 && !chain.include?(nil)
    end

    def trusted?(value)
      address = IPAddr.new(value.to_s)
      @networks.any? { |network| network.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
