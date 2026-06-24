# frozen_string_literal: true

require "webrick"

require_relative "protected_page"
require_relative "protection_store"

module LyraSite
  class ProtectedStaticServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, options = {})
      super(server)
      @protection_store = options.fetch(:protection_store)
      @access_session = options.fetch(:access_session)
      @file_handler = WEBrick::HTTPServlet::FileHandler.new(
        server,
        options.fetch(:static_root),
        { FancyIndexing: false }
      )
    end

    def service(request, response)
      return @file_handler.service(request, response) unless protected_method?(request)

      url = ProtectionStore.canonical_url(request.path)
      entry = @protection_store.find(url)

      if entry && !@access_session.authorized?(request, url)
        ProtectedPage.render(response, url: url, title: entry.fetch("title"))
      else
        @file_handler.service(request, response)
        disable_cache(response) if entry
      end
    end

    private

    def protected_method?(request)
      request.request_method == "GET" || request.request_method == "HEAD"
    end

    def disable_cache(response)
      response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
      response["Pragma"] = "no-cache"
    end
  end
end
