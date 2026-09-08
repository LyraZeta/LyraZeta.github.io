# frozen_string_literal: true

require "uri"
require "webrick"

require_relative "protection_store"

module LyraSite
  class VisitRecorder
    def initialize(store:, client_address:)
      @store = store
      @client_address = client_address
    end

    def record(request, response)
      path = clean(request.path, 2048)
      return unless request.request_method == "GET"
      return if path.match?(%r{\A/(?:admin|api|unlock)(?:/|\z)})
      return unless File.extname(path).empty? || path.match?(/\.html?\z/i)

      agent = clean(request["User-Agent"], 512)
      started = request.instance_variable_get(:@lyra_started_at)
      duration = started ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round : 0
      @store.record_visit(
        ip: @client_address.ip(request) || "unknown", path: path, status: response.status,
        duration_ms: duration, referrer: referrer(request["Referer"]), user_agent: agent,
        bot: agent.match?(/bot|crawler|spider|slurp|headless|curl|wget/i)
      )
    rescue StandardError => error
      warn "Visit recording failed: #{error.class}"
    end

    private

    def clean(value, limit)
      ProtectionStore.utf8(value).gsub(/[[:cntrl:]]/, "").slice(0, limit)
    end

    def referrer(value)
      uri = URI.parse(clean(value, 2048))
      return "" unless %w[http https].include?(uri.scheme) && uri.host

      uri.user = nil
      uri.password = nil
      uri.query = nil
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      ""
    end
  end

  class HTTPServer < WEBrick::HTTPServer
    attr_accessor :visit_recorder

    def service(request, response)
      request.instance_variable_set(:@lyra_started_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
      super
    end

    def access_log(config, request, response)
      super
      @visit_recorder&.record(request, response)
    end
  end
end
