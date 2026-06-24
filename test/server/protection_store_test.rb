# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require_relative "../../server/lib/lyra_site/protection_store"

class ProtectionStoreTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "protected_posts.yml")
    @store = LyraSite::ProtectionStore.new(path: @path)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_protects_and_validates_password
    @store.protect(
      url: "/2026/03/hello-agents/",
      title: "hello-agents笔记",
      source_path: "_posts/LLM/2026-03-16-hello-agents.md",
      password: "secret"
    )

    assert @store.protected?("/2026/03/hello-agents/")
    assert @store.valid_password?("/2026/03/hello-agents/", "secret")
    refute @store.valid_password?("/2026/03/hello-agents/", "bad")
  end

  def test_canonicalizes_index_html_and_encoded_urls
    @store.protect(
      url: "/2026/01/历年考题/",
      title: "光电子学博资考题重点",
      source_path: "_posts/Course_Optoelectronics/2026-01-26-历年考题.md",
      password: "secret"
    )

    assert @store.protected?("/2026/01/%E5%8E%86%E5%B9%B4%E8%80%83%E9%A2%98/index.html")
  end

  def test_canonicalizes_ascii_8bit_utf8_bytes
    raw = "/2026/01/历年考题/".dup.force_encoding(Encoding::ASCII_8BIT)

    assert_equal "/2026/01/历年考题/", LyraSite::ProtectionStore.canonical_url(raw)
  end

  def test_unprotects_post
    @store.protect(url: "/post/", title: "Post", source_path: "_posts/post.md", password: "secret")
    @store.unprotect("/post/")

    refute @store.protected?("/post/")
  end
end
