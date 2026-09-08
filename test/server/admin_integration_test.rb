# frozen_string_literal: true

require "cgi"
require "fileutils"
require "minitest/autorun"
require "net/http"
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

  def request(path, form: nil, headers: {}, cookies: @cookies)
    req = form ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
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
