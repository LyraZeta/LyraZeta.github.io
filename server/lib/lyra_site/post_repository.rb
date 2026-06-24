# frozen_string_literal: true

require "date"
require "pathname"
require "yaml"

module LyraSite
  class PostRepository
    FRONT_MATTER_PATTERN = /\A---\s*\n(.*?)\n---\s*\n/m.freeze
    FILENAME_PATTERN = /\A(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})-(?<slug>.+)\.md\z/.freeze

    def initialize(root_path:)
      @root_path = Pathname(root_path).expand_path
      @posts_path = @root_path.join("_posts")
    end

    def all
      return [] unless @posts_path.directory?

      @posts_path.glob("**/*.md")
                 .filter_map { |path| parse_post(path) }
                 .sort_by { |post| [post.fetch(:date), post.fetch(:title)] }
                 .reverse
    end

    private

    def parse_post(path)
      filename = FILENAME_PATTERN.match(path.basename.to_s)
      return nil unless filename

      raw = path.read(encoding: "UTF-8")
      front_matter, body = split_front_matter(raw)
      metadata = load_metadata(front_matter)
      date = normalize_date(metadata["date"]) || filename_date(filename)
      raw_slug = filename[:slug]

      {
        id: "#{date.iso8601}-#{slugify(raw_slug)}",
        title: value_or_default(metadata["title"], raw_slug),
        date: date.iso8601,
        description: string_or_nil(metadata["description"]),
        tags: tags_from(metadata),
        category: category_for(path),
        url: build_url(date, raw_slug),
        source_path: path.relative_path_from(@root_path).to_s,
        excerpt: excerpt_from(body)
      }
    rescue Psych::SyntaxError => error
      warn "Skipping #{path}: invalid front matter (#{error.message})"
      nil
    end

    def split_front_matter(raw)
      match = FRONT_MATTER_PATTERN.match(raw)
      return ["", raw] unless match

      [match[1], raw[match.end(0)..] || ""]
    end

    def load_metadata(front_matter)
      return {} if front_matter.strip.empty?

      YAML.safe_load(
        front_matter,
        permitted_classes: [Date, Time],
        aliases: false
      ) || {}
    end

    def normalize_date(value)
      case value
      when Date
        value
      when Time
        value.to_date
      when String
        Date.parse(value)
      end
    rescue Date::Error
      nil
    end

    def filename_date(filename)
      Date.new(filename[:year].to_i, filename[:month].to_i, filename[:day].to_i)
    end

    def value_or_default(value, default)
      normalized = value.to_s.strip
      normalized.empty? ? default : normalized
    end

    def string_or_nil(value)
      normalized = value.to_s.strip
      normalized.empty? ? nil : normalized
    end

    def tags_from(metadata)
      raw_tags = metadata["tags"] || metadata["tag"] || []
      values = raw_tags.is_a?(Array) ? raw_tags : raw_tags.to_s.split(/[,\s]+/)

      values.map { |tag| tag.to_s.strip }.reject(&:empty?)
    end

    def category_for(path)
      category = path.dirname.relative_path_from(@posts_path).to_s
      category == "." ? nil : category
    end

    def build_url(date, raw_slug)
      "/#{date.year}/#{format('%02d', date.month)}/#{slugify(raw_slug)}/"
    end

    def slugify(value)
      value.to_s
           .gsub(/[！!?？,，.。:：;；'"“”‘’()\[\]{}【】]/u, "")
           .gsub(/[^\p{Alnum}_-]+/u, "-")
           .gsub(/-+/, "-")
           .gsub(/\A-|-+\z/, "")
    end

    def excerpt_from(body)
      body.to_s
          .gsub(/```.*?```/m, " ")
          .gsub(/!\[[^\]]*\]\([^)]+\)/, " ")
          .gsub(/<[^>]+>/, " ")
          .gsub(/[#>*_`|]/, " ")
          .split(/\n+/)
          .map(&:strip)
          .find { |line| !line.empty? }
          .to_s
          .slice(0, 180)
    end
  end
end
