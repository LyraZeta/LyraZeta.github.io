# frozen_string_literal: true

require "uri"
require "webrick"

require_relative "protected_page"
require_relative "protection_store"

module LyraSite
  class AccessServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, options = {})
      super(server)
      @protection_store = options.fetch(:protection_store)
      @access_session = options.fetch(:access_session)
      @client_address = options.fetch(:client_address)
    end

    def do_POST(request, response)
      url = ProtectionStore.canonical_url(request.query["url"])
      password = ProtectionStore.utf8(request.query["password"])
      entry = @protection_store.find(url)

      if entry && PasswordHasher.verify?(password, entry.fetch("password_hash"))
        # Redirect headers need an ASCII URI; the access cookie keeps the canonical path.
        target = URI::DEFAULT_PARSER.escape(url, /[^A-Za-z0-9\-._~\/]/)
        @access_session.grant(response, url, version: entry.fetch("password_hash"), secure: @client_address.secure?(request))
        response.set_redirect(WEBrick::HTTPStatus::SeeOther, target)
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
