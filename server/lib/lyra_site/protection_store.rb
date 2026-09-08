# frozen_string_literal: true

require "fileutils"
require "pathname"
require "time"
require "tempfile"
require "thread"
require "uri"
require "yaml"

require_relative "password_hasher"

module LyraSite
  class ProtectionStore
    class InvalidConfiguration < StandardError; end

    DEFAULT_DATA = { "posts" => [] }.freeze

    def self.utf8(value)
      text = value.to_s.dup
      text = text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::ASCII_8BIT
      text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
    end

    def self.canonical_url(value)
      raw = utf8(value).strip
      path = URI.parse(raw).path
      path = URI::DEFAULT_PARSER.unescape(path)
      path = utf8(path)
      path = "/" if path.empty?
      path = "/#{path}" unless path.start_with?("/")
      path = path.sub(%r{/index\.html\z}, "/")
      path = "#{path}/" if path != "/" && File.extname(path).empty? && !path.end_with?("/")
      path
    rescue URI::InvalidURIError
      raw.start_with?("/") ? raw : "/#{raw}"
    end

    def initialize(path:)
      @path = Pathname(path).expand_path
      @mutex = Mutex.new
      FileUtils.mkdir_p(@path.dirname)
    end

    def all
      read_data.fetch("posts").map do |entry|
        normalize_entry(entry) || raise(InvalidConfiguration, "invalid_protection_entry")
      end
    end

    def find(url)
      canonical = self.class.canonical_url(url)
      all.find { |entry| entry.fetch("url") == canonical }
    end

    def protected?(url)
      !find(url).nil?
    end

    def valid_password?(url, password)
      entry = find(url)
      return false unless entry

      PasswordHasher.verify?(password, entry.fetch("password_hash"))
    end

    def protect(url:, title:, source_path:, password:)
      canonical = self.class.canonical_url(url)
      normalized_password = password.to_s
      raise ArgumentError, "password_required" if normalized_password.empty?

      entry = {
        "url" => canonical,
        "title" => self.class.utf8(title),
        "source_path" => self.class.utf8(source_path),
        "password_hash" => PasswordHasher.hash(normalized_password),
        "updated_at" => Time.now.utc.iso8601
      }

      @mutex.synchronize do
        posts = all.reject { |item| item.fetch("url") == canonical }
        posts << entry
        write_data("posts" => posts.sort_by { |item| item.fetch("url") })
      end
    end

    def unprotect(url)
      canonical = self.class.canonical_url(url)
      @mutex.synchronize do
        write_data("posts" => all.reject { |entry| entry.fetch("url") == canonical })
      end
    end

    private

    def read_data
      return DEFAULT_DATA.dup unless @path.file?

      data = YAML.safe_load(@path.read(encoding: "UTF-8"), aliases: false) || {}
      unless data.is_a?(Hash) && data["posts"].is_a?(Array)
        raise InvalidConfiguration, "invalid_protection_config"
      end

      data
    end

    def write_data(data)
      Tempfile.create(["protected_posts", ".tmp"], @path.dirname, encoding: "UTF-8") do |file|
        file.write(YAML.dump(data))
        file.flush
        file.fsync
        File.rename(file.path, @path)
      end
    end

    def normalize_entry(entry)
      return nil unless entry.is_a?(Hash)

      url = self.class.canonical_url(entry["url"])
      password_hash = entry["password_hash"].to_s
      return nil if url.empty? || password_hash.empty?

      {
        "url" => url,
        "title" => self.class.utf8(entry["title"]),
        "source_path" => self.class.utf8(entry["source_path"]),
        "password_hash" => password_hash,
        "updated_at" => entry["updated_at"].to_s
      }
    end
  end
end
