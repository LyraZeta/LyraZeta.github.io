# frozen_string_literal: true

require "securerandom"
require "webrick"

require_relative "access_servlet"
require_relative "access_session"
require_relative "activity_store"
require_relative "admin_servlet"
require_relative "admin_session"
require_relative "api_servlet"
require_relative "client_address"
require_relative "post_repository"
require_relative "protected_static_servlet"
require_relative "protection_store"
require_relative "visit_recorder"

module LyraSite
  module Application
    module_function

    def build(root_path:, env: ENV, logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO), access_log: $stdout)
      static_root = File.expand_path(env.fetch("STATIC_ROOT", File.join(root_path, "_site")))
      data_dir = File.expand_path(env.fetch("DATA_DIR", File.join(root_path, "server/data")))
      raise ArgumentError, "DATA_DIR must be outside STATIC_ROOT" if data_dir == static_root || data_dir.start_with?("#{static_root}/")

      secret = env["APP_SECRET"].to_s
      if secret.empty?
        secret = SecureRandom.hex(32)
        logger.warn("APP_SECRET is not set. Access cookies will be invalidated on restart.")
      end
      repository = PostRepository.new(root_path: root_path)
      protection = ProtectionStore.new(path: File.join(data_dir, "protected_posts.yml"))
      activity = ActivityStore.new(path: File.join(data_dir, "activity.sqlite3"))
      address = ClientAddress.new(trusted_proxies: env.fetch("TRUSTED_PROXIES", "127.0.0.1/32,::1/128"))
      access = AccessSession.new(secret: secret)
      admin = AdminSession.new(secret: secret, username: env.fetch("ADMIN_USERNAME", "admin"), password: env["ADMIN_PASSWORD"].to_s)

      server = HTTPServer.new(
        BindAddress: env.fetch("BIND", "127.0.0.1"), Port: Integer(env.fetch("PORT", "4000")),
        DocumentRoot: static_root, DirectoryIndex: ["index.html"], Logger: logger,
        AccessLog: access_log ? [[access_log, '%h %t "%m %U" %s %b']] : [],
        ShutdownCallback: -> { activity.close }
      )
      server.visit_recorder = VisitRecorder.new(store: activity, client_address: address)
      server.mount("/api", ApiServlet, repository: repository, protection_store: protection)
      server.mount("/admin", AdminServlet, repository: repository, protection_store: protection,
                   activity_store: activity, admin_session: admin, client_address: address)
      server.mount("/unlock", AccessServlet, protection_store: protection, access_session: access, client_address: address)
      server.mount("/", ProtectedStaticServlet, static_root: static_root, protection_store: protection, access_session: access)
      server
    end
  end
end
