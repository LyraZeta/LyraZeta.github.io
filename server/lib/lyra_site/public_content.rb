# frozen_string_literal: true

require "nokogiri"

require_relative "protection_store"

module LyraSite
  class PublicContent
    def initialize(static_root:, protection_store:)
      @static_root = static_root
      @protection_store = protection_store
    end

    def serve(path, response)
      canonical = ProtectionStore.canonical_url(path)
      feed = canonical == "/feed.xml"
      listing = canonical == "/" || canonical.match?(%r{\A/page/\d+/\z})
      return false unless feed || listing

      relative = feed ? "feed.xml" : File.join(canonical.delete_prefix("/"), "index.html")
      file = File.join(@static_root, relative)
      return false unless File.file?(file)

      protected_urls = @protection_store.all.map { |entry| entry.fetch("url") }
      content = File.read(file, encoding: "UTF-8")
      content = feed ? filter_feed(content, protected_urls) : filter_listing(content, protected_urls) unless protected_urls.empty?
      # Serve the complete filtered representation, including for Range/conditional requests.
      response.status = 200
      response["Content-Type"] = "#{feed ? 'application/rss+xml' : 'text/html'}; charset=utf-8"
      response["Cache-Control"] = "no-store"
      response.body = content
      true
    end

    private

    def filter_listing(content, protected_urls)
      document = Nokogiri::HTML5.parse(content)
      document.css(".post-list > li").each do |item|
        link = item.at_css(".post-title a[href]")
        next unless link && protected_urls.include?(ProtectionStore.canonical_url(link["href"]))

        item.css(".excerpt").each { |excerpt| excerpt.content = "这篇文章已设置访问保护。" }
      end
      document.to_html
    end

    def filter_feed(content, protected_urls)
      document = Nokogiri::XML(content) { |config| config.strict.nonet }
      document.xpath("/rss/channel/item").each do |item|
        link = item.at_xpath("link")&.text
        item.remove if link && protected_urls.include?(ProtectionStore.canonical_url(link))
      end
      document.to_xml
    end
  end
end
