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



end
