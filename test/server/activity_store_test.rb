# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../server/lib/lyra_site/activity_store"

class ActivityStoreTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @time = Time.iso8601("2026-09-08T10:00:00+08:00")
    @path = File.join(@dir, "activity.sqlite3")
    @store = LyraSite::ActivityStore.new(path: @path, clock: -> { @time })
  end

  def teardown
    @store.close
    FileUtils.remove_entry(@dir)
  end

  def visit(**values)
    @store.record_visit(**{ ip: "203.0.113.5", path: "/post/", status: 200, duration_ms: 5, referrer: "", user_agent: "Browser", bot: false }.merge(values))
  end

  def test_persistence_and_private_file_permissions
    visit
    @store.close
    @store = LyraSite::ActivityStore.new(path: @path, clock: -> { @time })
    assert_equal 1, @store.visits[:total]
    assert_equal 0o600, File.stat(@path).mode & 0o777
  end

  def test_filters_pagination_and_parameter_binding
    35.times { visit }
    visit(ip: "2001:db8::1", path: "/missing/", status: 404, bot: true)
    assert_equal 6, @store.visits({ "page" => "2" })[:rows].length
    assert_equal 1, @store.visits({ "ip" => "2001:db8", "status" => "4", "bot" => "1" })[:total]
    assert_equal 0, @store.visits({ "path" => "' OR 1=1 --" })[:total]
    assert_equal 0, @store.visits({ "path" => "%" })[:total]
    assert_equal 1, @store.visits({ "page" => "-2" })[:page]
    assert_raises(Date::Error) { @store.visits({ "from" => "invalid" }) }
  end

  def test_daily_counts_and_inclusive_date_filter_use_shanghai_time
    @time = Time.iso8601("2026-09-07T23:59:59+08:00")
    visit
    @time += 1
    visit(ip: "203.0.113.6", status: 404, bot: true)
    stats = @store.overview
    assert_equal 7, stats[:trend].length
    assert_equal 1, stats[:trend].last["views"]
    assert_equal 2, stats[:summary]["unique_ips"]
    assert_equal 1, stats[:summary]["errors"]
    assert_equal 1, stats[:summary]["bots"]
    assert_equal 1, @store.visits({ "from" => "2026-09-07", "to" => "2026-09-07" })[:total]
  end

  def test_disable_cleanup_and_clear_preserve_audit
    visit
    @store.audit(actor: "admin", ip: "127.0.0.1", action: "login")
    @store.update_settings(enabled: false, retention_days: 1)
    visit
    assert_equal 1, @store.visits[:total]
    @time += 86_401
    assert_equal 0, @store.visits[:total]
    assert_equal 0, @store.audit_events[:total]
    @store.audit(actor: "admin", ip: "127.0.0.1", action: "clear_visits")
    @store.clear_visits
    assert_equal 1, @store.audit_events[:total]
    assert_raises(ArgumentError) { @store.update_settings(enabled: true, retention_days: 0) }
    assert_equal "0", @store.settings["enabled"]
  end

  def test_concurrent_writes_do_not_drop_visits
    threads = 5.times.map { Thread.new { 20.times { visit } } }
    threads.each(&:value)
    assert_equal 100, @store.visits[:total]
  end

  def test_allowlist_normalizes_exact_addresses_and_persists_independently_of_logs
    assert_empty @store.allowed_ips
    assert_equal "203.0.113.5", @store.add_allowed_ip(ip: " ::ffff:203.0.113.5 ", note: " Laptop ")
    @store.add_allowed_ip(ip: "2001:0db8:0000:0000:0000:0000:0000:0001", note: "IPv6")
    assert @store.allowed_ip?("203.0.113.5")
    assert @store.allowed_ip?("::ffff:203.0.113.5")
    assert @store.allowed_ip?("2001:db8::1")
    refute @store.allowed_ip?("203.0.113.50")
    refute @store.allowed_ip?(nil)
    assert_raises(ArgumentError) { @store.add_allowed_ip(ip: "203.0.113.5", note: "overwrite") }
    assert_equal "Laptop", @store.allowed_ips.find { |entry| entry["ip"] == "203.0.113.5" }["note"]
    visit
    @store.update_settings(enabled: false, retention_days: 1)
    @time += 86_401
    @store.visits
    @store.clear_visits
    @store.close
    @store = LyraSite::ActivityStore.new(path: @path, clock: -> { @time })
    assert_equal 2, @store.allowed_ips.length
    assert @store.allowed_ip?("203.0.113.5")
    assert_equal "2001:db8::1", @store.remove_allowed_ip("2001:0db8::1")
    refute @store.allowed_ip?("2001:db8::1")
    assert_raises(ArgumentError) { @store.remove_allowed_ip("2001:db8::1") }
  end

  def test_allowlist_rejects_ranges_wildcards_hostnames_and_invalid_values
    [nil, "", "*", "203.0.113.1/32", "0.0.0.0/0", "::/0", "2001:db8::1%eth0", "[::1]", "localhost",
     "203.0.113.5:80", "203.0.113.1,203.0.113.2", "1.2.3", "256.1.1.1", "203.0.113.5\u0000", "' OR 1=1 --", "1" * 100].each do |ip|
      assert_raises(ArgumentError, ip.inspect) { @store.add_allowed_ip(ip: ip) }
      refute @store.allowed_ip?(ip), ip.inspect
    end
    ["x" * 121, "note\nwith newline", "note\u0000"].each do |note|
      assert_raises(ArgumentError) { @store.add_allowed_ip(ip: "203.0.113.5", note: note) }
    end
    assert_empty @store.allowed_ips
  end

  def test_allowlist_migration_preserves_existing_activity_data
    visit
    @store.update_settings(enabled: false, retention_days: 14)
    @store.close
    db = SQLite3::Database.new(@path)
    db.execute("DROP TABLE ip_allowlist")
    db.close
    @store = LyraSite::ActivityStore.new(path: @path, clock: -> { @time })
    assert_empty @store.allowed_ips
    assert_equal 1, @store.visits[:total]
    assert_equal({ "enabled" => "0", "retention_days" => "14" }, @store.settings)
  end
end
