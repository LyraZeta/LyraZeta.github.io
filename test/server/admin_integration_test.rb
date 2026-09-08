# frozen_string_literal: true

require "cgi"
require "fileutils"
require "minitest/autorun"
require "net/http"
require "nokogiri"
require "stringio"
require "timeout"
require "tmpdir"
require_relative "../../server/lib/lyra_site/application"

class AdminIntegrationTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p([File.join(@dir, "_site/2026/09/test"), File.join(@dir, "_posts"), File.join(@dir, "_site/css")])
    File.write(File.join(@dir, "_site/index.html"), "<h1>Home</h1>")
    File.write(File.join(@dir, "_site/feed.xml"), '<rss><channel><item><link>https://example.test/2026/09/test/</link><description>PRIVATE CONTENT</description></item><item><link>https://example.test/public/</link><description>PUBLIC CONTENT</description></item></channel></rss>')
    File.write(File.join(@dir, "_site/css/test.css"), "body {}")
    File.write(File.join(@dir, "_site/2026/09/test/index.html"), "<h1>PRIVATE CONTENT</h1>")
    File.write(File.join(@dir, "_posts/2026-09-01-test.md"), "---\ntitle: Test Article\n---\nPost content\n")
    @log = StringIO.new
    @server = LyraSite::Application.build(root_path: @dir, env: { "PORT" => "0", "ADMIN_PASSWORD" => "test-password", "APP_SECRET" => "test-secret" },
                                         logger: WEBrick::Log.new(@log, WEBrick::Log::ERROR), access_log: nil)
    @thread = Thread.new { @server.start }
    Timeout.timeout(5) { sleep 0.005 until @server.status == :Running }
    @port = @server[:Port]
    @cookies = {}
  end

  def teardown
    @server&.shutdown
    @thread&.join(5)
    FileUtils.remove_entry(@dir)
  end

  def request(path, form: nil, headers: {}, cookies: @cookies, head: false)
    req = form ? Net::HTTP::Post.new(path) : (head ? Net::HTTP::Head.new(path) : Net::HTTP::Get.new(path))
    req.set_form_data(form) if form
    req["Cookie"] = cookies.map { |key, value| "#{key}=#{value}" }.join("; ")
    headers.each { |key, value| req[key] = value }
    res = Net::HTTP.start("127.0.0.1", @port, nil) { |http| http.request(req) }
    res.get_fields("Set-Cookie").to_a.each { |header| key, value = header.split(";", 2).first.split("=", 2); cookies[key] = value }
    res.body&.force_encoding(Encoding::UTF_8) if res["Content-Type"].to_s.include?("charset=utf-8")
    res
  end

  def csrf(response)
    CGI.unescapeHTML(response.body[/name="csrf_token" value="([^"]+)"/, 1].to_s)
  end

  def login
    page = request("/admin/login")
    res = request("/admin/login", form: { username: "admin", password: "test-password", csrf_token: csrf(page) })
    assert_equal "303", res.code
    csrf(request("/admin"))
  end

  def database
    db = SQLite3::Database.new(File.join(@dir, "server/data/activity.sqlite3"))
    yield db
  ensure
    db&.close
  end

  def wait_for_visit_count(count)
    Timeout.timeout(5) do
      loop do
        break if database { |db| db.get_first_value("SELECT COUNT(*) FROM visits") } == count
        sleep 0.01
      end
    end
  end

  def test_admin_pages_and_export_require_login_and_valid_csrf
    %w[/admin /admin/visits /admin/audit /admin/settings /admin/visits.csv].each do |path|
      assert_equal "303", request(path).code
    end
    assert_equal "403", request("/admin/login", form: { username: "admin", password: "test-password" }).code
    token = login
    %w[/admin /admin/posts /admin/visits /admin/audit /admin/settings].each do |path|
      res = request(path)
      assert_equal "200", res.code, @log.string
      assert_equal "no-store", res["Cache-Control"]
      assert_includes res.body, "LyraZeta"
    end
    assert_equal "403", request("/admin/settings", form: { retention_days: "30" }).code
    assert_equal "404", request("/admin/unknown").code
    assert_equal "404", request("/admin/assets/../data/activity.sqlite3").code
    old_cookies = @cookies.dup
    assert_equal "303", request("/admin/logout", form: { csrf_token: token }).code
    assert_equal "303", request("/admin/visits", cookies: old_cookies).code
  end

  def test_ip_tracking_redacts_urls_escapes_html_and_records_final_errors
    agent = '=HYPERLINK("bad") <script>alert(1)</script>'
    request("/?password=secret", headers: { "X-Forwarded-For" => "1.2.3.4, 203.0.113.8", "User-Agent" => agent,
                                          "Referer" => "https://user:secret@example.test/page?token=secret#private" })
    request("/missing/")
    request("/css/test.css")
    request("/api/health")
    wait_for_visit_count(2)
    database do |db|
      assert_equal ["203.0.113.8", "/", "https://example.test/page"], db.get_first_row("SELECT ip,path,referrer FROM visits ORDER BY id LIMIT 1")
      assert_equal 404, db.get_first_value("SELECT status FROM visits WHERE path = '/missing/'")
    end
    login
    res = request("/admin/visits?ip=203.0.113.8")
    assert_includes res.body, "&lt;script&gt;"
    refute_includes res.body, "<script>alert(1)</script>"
    assert_equal "400", request("/admin/visits?from=invalid").code
    csv = request("/admin/visits.csv?ip=203.0.113.8")
    rows = CSV.parse(csv.body.delete_prefix("\uFEFF"))
    assert_equal 2, rows.length
    assert rows.last[6].start_with?("'="), rows.last[6]
    refute_includes csv.body, "secret"
    assert_equal "no-store", csv["Cache-Control"]
  end

  def test_protection_password_rotation_and_unprotect_flow
    token = login
    url = "/2026/09/test/"
    form = { csrf_token: token, url: url, action: "protect", password: "first-password" }
    assert_equal "303", request("/admin/protections", form: form).code
    assert_equal "200", request("/admin/posts?edit=%2F2026%2F09%2Ftest%2F").code
    visitor = {}
    refute_includes request(url, cookies: visitor).body, "PRIVATE CONTENT"
    assert_equal "303", request("/unlock", form: { url: url, password: "first-password" }, cookies: visitor).code
    assert_includes request(url, cookies: visitor).body, "PRIVATE CONTENT"
    assert_equal "303", request("/admin/protections", form: form.merge(password: "second-password")).code
    refute_includes request("#{url}index.html", cookies: visitor).body, "PRIVATE CONTENT"
    refute_includes request("/unlock", form: { url: url, password: "first-password" }, cookies: visitor).body, "PRIVATE CONTENT"
    assert_equal "303", request("/admin/protections", form: form.merge(action: "unprotect")).code
    assert_includes request(url, cookies: {}).body, "PRIVATE CONTENT"
    audit = request("/admin/audit")
    assert_includes audit.body, "设置文章密码"
    refute_includes audit.body, "first-password"
  end

  def test_settings_persist_and_clear_requires_confirmation
    token = login
    request("/")
    wait_for_visit_count(1)
    assert_equal "303", request("/admin/settings", form: { csrf_token: token, retention_days: "14" }).code
    request("/")
    assert_equal "0", database { |db| db.get_first_value("SELECT value FROM settings WHERE key = 'enabled'") }
    assert_equal "400", request("/admin/visits/clear", form: { csrf_token: token }).code
    assert_equal 1, database { |db| db.get_first_value("SELECT COUNT(*) FROM visits") }
    assert_equal "303", request("/admin/visits/clear", form: { csrf_token: token, confirmation: "DELETE" }).code
    assert_equal 0, database { |db| db.get_first_value("SELECT COUNT(*) FROM visits") }
    assert_includes request("/admin/audit").body, "清空访问日志"
  end

  def test_allowlist_management_requires_admin_and_csrf_and_escapes_notes
    form = { action: "add", ip: "203.0.113.5", note: '<script>alert("note")</script>' }
    assert_equal "303", request("/admin/allowlist", form: form, cookies: {}).code
    token = login
    assert_equal "403", request("/admin/allowlist", form: form).code
    assert_equal 0, database { |db| db.get_first_value("SELECT COUNT(*) FROM ip_allowlist") }
    res = request("/admin/allowlist", form: form.merge(csrf_token: token))
    assert_equal "303", res.code
    assert_equal "/admin/settings", URI.parse(res["Location"]).path
    assert_equal "ip-allowlist", URI.parse(res["Location"]).fragment
    settings = request("/admin/settings")
    doc = Nokogiri::HTML(settings.body)
    assert_equal 1, doc.css(".allowlist-table .ip-address").length
    assert_includes doc.at_css(".allowlist-table").text, form[:note]
    assert_empty doc.css(".allowlist-table script")
    duplicate = request("/admin/allowlist", form: form.merge(csrf_token: token, ip: "::ffff:203.0.113.5"))
    assert_equal "422", duplicate.code
    assert_includes duplicate.body, "该 IP 已在白名单中。"
    assert_equal token, csrf(duplicate)
    invalid = request("/admin/allowlist", form: form.merge(csrf_token: token, ip: "0.0.0.0/0"))
    assert_equal "422", invalid.code
    assert_includes invalid.body, "不支持网段"
    assert_equal 1, database { |db| db.get_first_value("SELECT COUNT(*) FROM ip_allowlist") }
    assert_equal "403", request("/admin/allowlist", form: { action: "remove", ip: form[:ip] }).code
    assert_equal "303", request("/admin/allowlist", form: { csrf_token: token, action: "remove", ip: form[:ip] }).code
    assert_equal 0, database { |db| db.get_first_value("SELECT COUNT(*) FROM ip_allowlist") }
    actions = database { |db| db.execute("SELECT action, target FROM audit_events WHERE action LIKE 'allowlist_%' ORDER BY id") }
    assert_equal [["allowlist_add", "203.0.113.5"], ["allowlist_remove", "203.0.113.5"]], actions
    assert_includes request("/admin/audit").body, "添加白名单 IP"
    assert_includes request("/admin/audit").body, "移除白名单 IP"
  end

  def test_allowlisted_visitors_read_all_articles_without_cookies_and_revocation_is_immediate
    write_tagged_post("中文文章", title: "中文文章", tags: ["Test"])
    FileUtils.mkdir_p(File.join(@dir, "_site/2026/09/中文文章"))
    File.write(File.join(@dir, "_site/2026/09/中文文章/index.html"), "<h1>PRIVATE CHINESE CONTENT</h1>")
    token = login
    urls = ["/2026/09/test/", "/2026/09/中文文章/"]
    urls.each do |url|
      assert_equal "303", request("/admin/protections", form: { csrf_token: token, action: "protect", url: url, password: "password" }).code
    end
    headers = { "X-Forwarded-For" => "203.0.113.5" }
    refute_includes request(urls.first, headers: headers, cookies: {}).body, "PRIVATE"
    assert_equal "303", request("/admin/allowlist", form: { csrf_token: token, action: "add", ip: "203.0.113.5" }).code
    visitor = {}
    urls.each do |url|
      encoded = URI::DEFAULT_PARSER.escape(url)
      [encoded, "#{encoded}index.html"].each do |path|
        res = request(path, headers: headers, cookies: visitor)
        assert_equal "200", res.code, @log.string
        assert_includes res.body, "PRIVATE"
        assert_nil res["Set-Cookie"]
        assert_includes res["Cache-Control"], "no-store"
        refute_includes request(path, cookies: {}).body, "PRIVATE"
      end
    end
    partial = request(urls.first, headers: headers.merge("Range" => "bytes=0-20"), cookies: visitor)
    assert_equal "206", partial.code
    assert_includes partial["Cache-Control"], "no-store"
    head = request(urls.first, headers: headers, cookies: visitor, head: true)
    assert_equal "200", head.code
    assert_includes head["Cache-Control"], "no-store"
    unlocked = request("/unlock", form: { url: urls.last, password: "" }, headers: headers, cookies: visitor)
    assert_equal "303", unlocked.code
    assert_nil unlocked["Set-Cookie"]
    assert_includes request(URI.parse(unlocked["Location"]).request_uri, headers: headers, cookies: visitor).body, "PRIVATE"
    assert_empty visitor
    assert_equal "303", request("/admin", headers: headers, cookies: visitor).code
    refute_includes request("/feed.xml", headers: headers, cookies: visitor).body, "PRIVATE"
    assert JSON.parse(request("/api/posts", headers: headers, cookies: visitor).body)["posts"].all? { |post| post["protected"] && post["excerpt"].nil? }
    assert_equal "303", request("/admin/allowlist", form: { csrf_token: token, action: "remove", ip: "203.0.113.5" }).code
    denied = request(urls.first, headers: headers.merge("Range" => "bytes=0-20", "If-Modified-Since" => Time.now.httpdate), cookies: visitor)
    assert_equal "200", denied.code
    refute_includes denied.body, "PRIVATE"
    assert_includes denied.body, "访问密码"
    assert_nil request("/unlock", form: { url: urls.last, password: "" }, headers: headers, cookies: visitor)["Location"]
  end


  def test_allowlist_uses_trusted_client_identity_not_spoofed_headers_or_proxy_fallback
    token = login
    request("/admin/protections", form: { csrf_token: token, action: "protect", url: "/2026/09/test/", password: "password" })
    %w[203.0.113.5 2001:db8::1 127.0.0.1].each do |ip|
      request("/admin/allowlist", form: { csrf_token: token, action: "add", ip: ip })
    end
    [nil, "203.0.113.5, 203.0.113.6", "bad, 203.0.113.5", "203.0.113.5,", "127.0.0.1"].each do |forwarded|
      headers = { "Client-IP" => "203.0.113.5", "X-Real-IP" => "203.0.113.5" }
      headers["X-Forwarded-For"] = forwarded if forwarded
      refute_includes request("/2026/09/test/", headers: headers, cookies: {}).body, "PRIVATE CONTENT"
    end
    %w[::ffff:203.0.113.5 2001:0db8:0000:0000:0000:0000:0000:0001].each do |forwarded|
      assert_includes request("/2026/09/test/", headers: { "X-Forwarded-For" => forwarded }, cookies: {}).body, "PRIVATE CONTENT"
    end
  end

  def test_unlock_redirects_to_chinese_articles_without_a_second_visit
    articles = [
      ["2026-06-25-阿丘科技-AI-Agent", "/2026/06/阿丘科技-AI-Agent/", "/2026/06/%E9%98%BF%E4%B8%98%E7%A7%91%E6%8A%80-AI-Agent/"],
      ["2025-08-01-一起环游世界", "/2025/08/一起环游世界/", "/2025/08/%E4%B8%80%E8%B5%B7%E7%8E%AF%E6%B8%B8%E4%B8%96%E7%95%8C/"]
    ]
    articles.each do |slug, url, _|
      File.write(File.join(@dir, "_posts/#{slug}.md"), "---\ntitle: Chinese Article\n---\nPost content\n")
      directory = File.join(@dir, "_site", url.delete_prefix("/"))
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, "index.html"), "<h1>PRIVATE CONTENT</h1>")
    end
    token = login
    articles.each do |_, url, encoded_url|
      res = request("/admin/protections", form: { csrf_token: token, action: "protect", url: url, password: "中文密码" })
      assert_equal "303", res.code
      visitor = {}
      page = request(encoded_url, cookies: visitor)
      refute_includes page.body, "PRIVATE CONTENT"
      submitted_url = Nokogiri::HTML(page.body).at_css('input[name="url"]')["value"]
      assert_equal url, submitted_url
      wrong = request("/unlock", form: { url: submitted_url, password: "wrong" }, cookies: visitor)
      assert_equal "200", wrong.code
      assert_includes wrong.body, "密码错误，请重试。"
      assert_nil wrong["Location"]
      assert_nil wrong["Set-Cookie"]

      [submitted_url, encoded_url].each do |target|
        visitor = {}
        unlocked = request("/unlock", form: { url: target, password: "中文密码" }, cookies: visitor,
                           headers: { "X-Forwarded-Proto" => "https" })
        assert_equal "303", unlocked.code, @log.string
        assert unlocked["Location"].ascii_only?
        location = URI.parse(unlocked["Location"])
        assert_equal encoded_url, location.path
        assert_nil location.query
        assert_nil location.fragment
        assert_includes unlocked["Set-Cookie"], "; Secure"
        article = request(location.request_uri, cookies: visitor)
        assert_equal "200", article.code
        assert_includes article.body, "PRIVATE CONTENT"
        assert_includes article["Cache-Control"], "no-store"
      end
    end
    refute_includes request(articles.first.last, cookies: {}).body, "PRIVATE CONTENT"
    unknown = request("/unlock", form: { url: "/2026/06/not-a-post/", password: "中文密码" }, cookies: {})
    assert_nil unknown["Location"]
    assert_nil unknown["Set-Cookie"]
  end

  def test_proxy_https_cookies_and_static_asset_allowlist
    res = request("/admin/login", headers: { "X-Forwarded-Proto" => "https" })
    assert_includes res["Set-Cookie"], "; Secure"
    assert_includes res["Set-Cookie"], "; HttpOnly"
    %w[admin.css admin.js icons.svg].each do |name|
      assert_equal "200", request("/admin/assets/#{name}").code
    end
    assert_equal "404", request("/admin/assets/application.rb").code
    assert_equal "404", request("/server/data/activity.sqlite3").code
  end

  def write_tagged_post(slug, title:, tags:)
    metadata = { "title" => title, "tags" => tags }
    File.write(File.join(@dir, "_posts/2026-09-02-#{slug}.md"), "#{metadata.to_yaml}---\nPost content\n")
  end

  def posts_document(filters = {})
    res = request("/admin/posts?#{URI.encode_www_form(filters)}")
    assert_equal "200", res.code, @log.string
    Nokogiri::HTML(res.body)
  end

  def test_posts_default_to_tag_collections_with_unique_counts
    write_tagged_post("alpha", title: "Alpha", tags: ["Course", "Course", "光学 & 设计"])
    write_tagged_post("beta", title: "Beta", tags: ["Course2"])
    write_tagged_post("gamma", title: "Gamma", tags: ["Course"])
    token = login
    request("/admin/protections", form: { csrf_token: token, action: "protect", url: "/2026/09/alpha/", password: "test" })
    doc = posts_document
    assert_empty doc.css(".posts-table")
    assert_equal ["Course", "Course2", "光学 & 设计", "未标记"], doc.css(".collection-title h3").map(&:text)
    assert_includes doc.at_css("#collections-heading").parent.text, "4 个集合 · 4 篇文章"
    course = doc.at_css(".post-collection")
    assert_equal "2", course.at_css(".collection-count strong").text
    assert_equal ["1 公开", "1 已保护"], course.css(".collection-states > span").map(&:text)
    assert_equal "Gamma", course.at_css(".collection-latest p").text

    doc = posts_document("tag" => "Course")
    assert_equal ["Gamma", "Alpha"], doc.css(".posts-table strong").map(&:text)
    doc = posts_document("tag" => "光学 & 设计")
    assert_equal ["Alpha"], doc.css(".posts-table strong").map(&:text)
    doc = posts_document("untagged" => "1")
    assert_equal ["Test Article"], doc.css(".posts-table strong").map(&:text)
  end

  def test_collection_filters_apply_before_counts_and_preserve_tag_scope
    write_tagged_post("alpha", title: "Alpha", tags: ["Course", "光学"])
    write_tagged_post("beta", title: "Beta", tags: ["Course"])
    token = login
    request("/admin/protections", form: { csrf_token: token, action: "protect", url: "/2026/09/alpha/", password: "test" })
    doc = posts_document("state" => "protected", "q" => "Alpha")
    assert_equal ["Course", "光学"], doc.css(".collection-title h3").map(&:text)
    assert_includes doc.at_css("#collections-heading").parent.text, "2 个集合 · 1 篇文章"
    doc.css(".post-collection").each do |link|
      filters = URI.decode_www_form(URI.parse(link["href"]).query).to_h
      assert_equal "protected", filters["state"]
      assert_equal "Alpha", filters["q"]
      assert_equal "1", link.at_css(".collection-count strong").text
    end
    doc = posts_document("tag" => "Course", "state" => "public")
    assert_equal ["Beta"], doc.css(".posts-table strong").map(&:text)
    assert_equal "Course", doc.at_css('.post-filters input[name="tag"]')["value"]
    reset = doc.at_css('a[title="重置筛选"]')["href"]
    assert_equal({ "tag" => "Course" }, URI.decode_www_form(URI.parse(reset).query).to_h)
    doc = posts_document("tag" => "Course", "q" => "missing")
    assert_includes doc.at_css(".empty").text, "没有符合条件的文章"
    assert_equal "Course", doc.at_css("#collection-heading").text
    doc = posts_document("q" => "missing")
    assert_empty doc.css(".post-collection")
    assert_includes doc.at_css(".empty").text, "没有符合条件的文章"
  end

  def test_collection_pagination_and_protection_actions_keep_context
    31.times { |index| write_tagged_post("post-#{index}", title: format("分页 %02d", index), tags: ["光学 & 设计"]) }
    token = login
    filters = { "tag" => "光学 & 设计", "q" => "分页", "state" => "public" }
    doc = posts_document(filters)
    assert_equal 30, doc.css(".posts-table strong").length
    following = doc.at_css('.pagination a[aria-label="下一页"]')["href"]
    assert_equal filters.merge("page" => "2"), URI.decode_www_form(URI.parse(following).query).to_h
    doc = posts_document(filters.merge("page" => "999"))
    assert_equal ["分页 00"], doc.css(".posts-table strong").map(&:text)
    edit = doc.at_css('a[title="管理访问密码"]')["href"]
    edit_filters = URI.decode_www_form(URI.parse(edit).query).to_h
    assert_equal filters.merge("page" => "2", "edit" => "/2026/09/post-0/"), edit_filters
    doc = posts_document(edit_filters)
    hidden = doc.css('.edit-form input[type="hidden"]').to_h { |input| [input["name"], input["value"]] }
    assert_equal filters.merge("page" => "2"), hidden.slice(*filters.keys, "page")
    res = request("/admin/protections", form: hidden.merge("action" => "protect", "password" => "test", "return_to" => "https://example.test/"))
    assert_equal "303", res.code
    location = URI.parse(res["Location"])
    assert_equal "/admin/posts", location.path
    assert_equal filters.merge("page" => "2", "notice" => "protected"), URI.decode_www_form(location.query).to_h
    doc = posts_document(filters.merge("page" => "2"))
    assert_equal 30, doc.css(".posts-table strong").length
    assert_includes doc.at_css(".pagination").text, "1 / 1"
    res = request("/admin/protections", form: hidden.merge("action" => "unprotect", "csrf_token" => token))
    assert_equal "303", res.code
    assert_equal filters.merge("page" => "2", "notice" => "public"), URI.decode_www_form(URI.parse(res["Location"]).query).to_h
  end

  def test_tag_names_are_escaped_and_do_not_collide_with_untagged
    tag = '<script>alert("tag")</script> & 光学'
    write_tagged_post("special", title: "Special", tags: [tag, "未标记"])
    login
    doc = posts_document
    assert_equal 3, doc.css(".post-collection").length
    assert_empty doc.css(".post-collections script")
    link = doc.css(".post-collection").find { |node| node.at_css("h3").text == tag }
    assert_equal tag, URI.decode_www_form(URI.parse(link["href"]).query).to_h["tag"]
    doc = posts_document("tag" => tag, "untagged" => "1")
    assert_equal tag, doc.at_css("#collection-heading").text
    assert_empty doc.css("#collection-heading script")
    assert_equal ["Special"], doc.css(".posts-table strong").map(&:text)
    assert_equal ["Special"], posts_document("tag" => "未标记").css(".posts-table strong").map(&:text)
    assert_equal ["Test Article"], posts_document("untagged" => "1").css(".posts-table strong").map(&:text)
    doc = posts_document("tag" => "unknown")
    assert_equal "unknown", doc.at_css("#collection-heading").text
    assert_empty doc.css(".posts-table strong")
  end

  def test_protected_posts_are_not_leaked_through_feed_api_or_listing_ranges
    html = '<!doctype html><html><head><title>Home</title></head><body><ol class="post-list"><li><article><h2 class="post-title"><a href="/2026/09/test/">Test</a></h2><p class="excerpt">PRIVATE CONTENT</p></article></li></ol></body></html>'
    File.write(File.join(@dir, "_site/index.html"), html)
    FileUtils.mkdir_p(File.join(@dir, "_site/page/2"))
    File.write(File.join(@dir, "_site/page/2/index.html"), html)
    token = login
    request("/admin/protections", form: { csrf_token: token, action: "protect", url: "/2026/09/test/", password: "test" })
    %w[/ /index.html /page/2/ /page/2/index.html /feed.xml].each do |path|
      res = request(path, headers: { "Range" => "bytes=0-10000", "If-Modified-Since" => Time.now.httpdate })
      assert_equal "200", res.code
      assert_equal "no-store", res["Cache-Control"]
      refute_includes res.body, "PRIVATE CONTENT"
    end
    assert_includes request("/feed.xml").body, "PUBLIC CONTENT"
    metadata = JSON.parse(request("/api/posts").body).fetch("posts").first
    assert metadata["protected"]
    assert_nil metadata["excerpt"]
    assert_nil metadata["description"]
    refute metadata.key?("source_path")
  end
end
