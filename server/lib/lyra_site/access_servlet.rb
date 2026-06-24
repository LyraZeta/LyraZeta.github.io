# frozen_string_literal: true

require "webrick"

require_relative "protected_page"
require_relative "protection_store"

module LyraSite
  class AccessServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, options = {})
      super(server)
      @protection_store = options.fetch(:protection_store)
      @access_session = options.fetch(:access_session)
    end

    def do_POST(request, response)
      url = ProtectionStore.canonical_url(request.query["url"])
      password = ProtectionStore.utf8(request.query["password"])
      entry = @protection_store.find(url)

      if entry && @protection_store.valid_password?(url, password)
        @access_session.grant(response, url)
        response.set_redirect(WEBrick::HTTPStatus::SeeOther, url)
      else
        ProtectedPage.render(
          response,
          url: url,
          title: entry && entry.fetch("title"),
          error: "密码错误，请重试。"
        )
      end
    end
  end
end
