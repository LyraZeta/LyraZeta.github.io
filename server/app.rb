#!/usr/bin/env ruby
# frozen_string_literal: true

require "webrick"

require_relative "lib/lyra_site/access_servlet"
require_relative "lib/lyra_site/access_session"
require_relative "lib/lyra_site/admin_servlet"
require_relative "lib/lyra_site/api_servlet"
require_relative "lib/lyra_site/post_repository"
require_relative "lib/lyra_site/protected_static_servlet"
require_relative "lib/lyra_site/protection_store"

ROOT_PATH = File.expand_path("..", __dir__)
STATIC_ROOT = File.join(ROOT_PATH, "_site")
PORT = Integer(ENV.fetch("PORT", "4000"))
BIND_ADDRESS = ENV.fetch("BIND", "127.0.0.1")

unless File.exist?(File.join(STATIC_ROOT, "index.html"))
  warn "Static site is missing. Run `bundle exec jekyll build` before starting the backend."
end

repository = LyraSite::PostRepository.new(root_path: ROOT_PATH)
protection_store = LyraSite::ProtectionStore.new(
  path: File.join(ROOT_PATH, "server/data/protected_posts.yml")
)
app_secret = ENV["APP_SECRET"].to_s

if app_secret.empty?
  require "securerandom"
  app_secret = SecureRandom.hex(32)
  warn "APP_SECRET is not set. Access cookies will be invalidated on every restart."
end

access_session = LyraSite::AccessSession.new(secret: app_secret)

server = WEBrick::HTTPServer.new(
  BindAddress: BIND_ADDRESS,
  Port: PORT,
  DocumentRoot: STATIC_ROOT,
  DirectoryIndex: ["index.html"],
  AccessLog: [[WEBrick::Log.new($stdout), WEBrick::AccessLog::COMBINED_LOG_FORMAT]],
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO)
)

server.mount("/api", LyraSite::ApiServlet, repository: repository)
server.mount("/admin", LyraSite::AdminServlet, repository: repository, protection_store: protection_store)
server.mount("/unlock", LyraSite::AccessServlet, protection_store: protection_store, access_session: access_session)
server.mount(
  "/",
  LyraSite::ProtectedStaticServlet,
  static_root: STATIC_ROOT,
  protection_store: protection_store,
  access_session: access_session
)

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }

puts "LyraZeta site backend listening on http://#{BIND_ADDRESS}:#{PORT}"
server.start
