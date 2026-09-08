#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "lib/lyra_site/application"

ROOT_PATH = File.expand_path("..", __dir__)
STATIC_ROOT = ENV.fetch("STATIC_ROOT", File.join(ROOT_PATH, "_site"))

unless File.exist?(File.join(STATIC_ROOT, "index.html"))
  warn "Static site is missing. Run `bundle exec jekyll build` before starting the backend."
end

server = LyraSite::Application.build(root_path: ROOT_PATH)

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }

puts "LyraZeta site backend listening on http://#{server[:BindAddress]}:#{server[:Port]}"
server.start
