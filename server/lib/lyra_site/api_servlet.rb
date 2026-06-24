# frozen_string_literal: true

require "json"
require "time"
require "webrick"

module LyraSite
  class ApiServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, options = {})
      super(server)
      @repository = options.fetch(:repository)
    end

    def do_GET(request, response)
      case request.path
      when "/api/health"
        json(response, health_payload)
      when "/api/posts"
        posts(request, response)
      else
        json(response, { error: "not_found" }, status: 404)
      end
    rescue StandardError => error
      warn "API error: #{error.class}: #{error.message}"
      json(response, { error: "internal_server_error" }, status: 500)
    end

    private

    def health_payload
      {
        status: "ok",
        service: "lyrazeta-site",
        environment: ENV.fetch("APP_ENV", "development"),
        time: Time.now.utc.iso8601
      }
    end

    def posts(request, response)
      limit, error = parse_limit(request.query["limit"])
      return json(response, { error: error }, status: 400) if error

      posts = filtered_posts(request.query["tag"])
      total_count = posts.length
      posts = posts.first(limit) unless limit.nil?

      json(response, { count: total_count, posts: posts })
    end

    def filtered_posts(tag)
      posts = @repository.all
      normalized_tag = tag.to_s.strip
      return posts if normalized_tag.empty?

      posts.select { |post| post.fetch(:tags).include?(normalized_tag) }
    end

    def parse_limit(value)
      return [nil, nil] if value.nil? || value.to_s.strip.empty?

      limit = Integer(value, 10)
      return [limit, nil] if limit >= 0

      [nil, "limit_must_be_non_negative"]
    rescue ArgumentError
      [nil, "limit_must_be_integer"]
    end

    def json(response, payload, status: 200)
      response.status = status
      response["Content-Type"] = "application/json; charset=utf-8"
      response["Cache-Control"] = "no-store"
      response.body = JSON.generate(payload)
    end
  end
end
