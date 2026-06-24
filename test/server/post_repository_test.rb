# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require_relative "../../server/lib/lyra_site/post_repository"

class PostRepositoryTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @posts_dir = File.join(@root, "_posts")
    FileUtils.mkdir_p(File.join(@posts_dir, "notes"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_reads_post_metadata
    write_post(
      "notes/2026-06-24-测试文章！.md",
      <<~MARKDOWN
        ---
        layout: post
        title: "测试文章"
        date: 2026-06-24
        description: "后端化第一步"
        tag: 动态
        ---

        # 标题

        正文第一段。
      MARKDOWN
    )

    post = repository.all.first

    assert_equal "测试文章", post.fetch(:title)
    assert_equal "2026-06-24", post.fetch(:date)
    assert_equal ["动态"], post.fetch(:tags)
    assert_equal "notes", post.fetch(:category)
    assert_equal "/2026/06/测试文章/", post.fetch(:url)
    assert_equal "标题", post.fetch(:excerpt)
  end

  def test_supports_tag_arrays_and_jekyll_style_chinese_slugs
    write_post(
      "2025-06-26-成都智绘阁科技面经——算法实习生.md",
      <<~MARKDOWN
        ---
        layout: post
        title: "成都智绘阁科技面经"
        date: 2025-06-26
        tags:
          - 面经
          - 算法
        ---

        面试记录。
      MARKDOWN
    )

    post = repository.all.first

    assert_equal ["面经", "算法"], post.fetch(:tags)
    assert_equal "/2025/06/成都智绘阁科技面经-算法实习生/", post.fetch(:url)
  end

  private

  def repository
    LyraSite::PostRepository.new(root_path: @root)
  end

  def write_post(relative_path, content)
    path = File.join(@posts_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content, mode: "w:UTF-8")
  end
end
