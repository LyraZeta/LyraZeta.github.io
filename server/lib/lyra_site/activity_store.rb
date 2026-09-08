# frozen_string_literal: true

require "date"
require "fileutils"
require "sqlite3"
require "thread"
require "time"

require_relative "client_address"

module LyraSite
  class ActivityStore
    PAGE_SIZE = 30
    EXPORT_LIMIT = 10_000
    TIME_OFFSET = "+08:00"
    DEFAULT_SETTINGS = { "enabled" => "1", "retention_days" => "30" }.freeze

    def initialize(path:, clock: -> { Time.now })
      @clock = clock
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::RDWR | File::CREAT, 0o600).close
      File.chmod(0o600, path)
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @db.busy_timeout = 3000
      @db.execute_batch(<<~SQL)
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS ip_allowlist (
          ip TEXT PRIMARY KEY, note TEXT NOT NULL, created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS visits (
          id INTEGER PRIMARY KEY, occurred_at INTEGER NOT NULL, ip TEXT NOT NULL,
          path TEXT NOT NULL, status INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
          referrer TEXT NOT NULL, user_agent TEXT NOT NULL, bot INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS visits_time ON visits(occurred_at);
        CREATE INDEX IF NOT EXISTS visits_ip_time ON visits(ip, occurred_at);
        CREATE TABLE IF NOT EXISTS audit_events (
          id INTEGER PRIMARY KEY, occurred_at INTEGER NOT NULL, actor TEXT NOT NULL,
          ip TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS audit_time ON audit_events(occurred_at);
      SQL
      @settings = DEFAULT_SETTINGS.merge(@db.execute("SELECT key, value FROM settings").to_h { |row| [row["key"], row["value"]] })
      @last_cleanup = 0
      @mutex.synchronize { cleanup! }
    end

    def settings
      @mutex.synchronize { @settings.dup }
    end

    def update_settings(enabled:, retention_days:)
      days = Integer(retention_days.to_s, 10)
      raise ArgumentError, "invalid_retention" unless (1..365).cover?(days)

      @mutex.synchronize do
        values = { "enabled" => enabled ? "1" : "0", "retention_days" => days.to_s }
        @db.transaction do
          values.each { |key, value| @db.execute("INSERT OR REPLACE INTO settings VALUES (?, ?)", [key, value]) }
        end
        @settings = values
        cleanup!
      end
    end

    def record_visit(ip:, path:, status:, duration_ms:, referrer:, user_agent:, bot:)
      @mutex.synchronize do
        cleanup_if_due!
        return if @settings["enabled"] != "1"

        @db.execute(
          "INSERT INTO visits (occurred_at, ip, path, status, duration_ms, referrer, user_agent, bot) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          [@clock.call.to_i, ip, path, status, duration_ms, referrer, user_agent, bot ? 1 : 0]
        )
      end
    end

    def allowed_ips
      @mutex.synchronize { @db.execute("SELECT ip, note, created_at FROM ip_allowlist ORDER BY created_at DESC, ip") }
    end

    def allowed_ip?(value)
      ip = ClientAddress.normalize_ip(value)
      return false unless ip

      @mutex.synchronize { !@db.get_first_value("SELECT 1 FROM ip_allowlist WHERE ip = ?", [ip]).nil? }
    end

    def add_allowed_ip(ip:, note: "")
      ip = normalize_allowed_ip(ip)
      note = note.to_s
      raise ArgumentError, "invalid_note" if note.length > 120 || note.match?(/[[:cntrl:]]/)
      note = note.strip

      @mutex.synchronize do
        @db.execute("INSERT INTO ip_allowlist (ip, note, created_at) VALUES (?, ?, ?)", [ip, note, @clock.call.to_i])
      end
      ip
    rescue SQLite3::ConstraintException
      raise ArgumentError, "duplicate_ip"
    end

    def remove_allowed_ip(value)
      ip = normalize_allowed_ip(value)
      @mutex.synchronize do
        @db.execute("DELETE FROM ip_allowlist WHERE ip = ?", [ip])
        raise ArgumentError, "unknown_ip" if @db.changes.zero?
      end
      ip
    end

    def audit(actor:, ip:, action:, target: "")
      @mutex.synchronize do
        cleanup_if_due!
        @db.execute("INSERT INTO audit_events (occurred_at, actor, ip, action, target) VALUES (?, ?, ?, ?, ?)",
                    [@clock.call.to_i, actor, ip, action, target])
      end
    end

    def visits(filters = {}, export: false)
      where, params = visit_conditions(filters)
      @mutex.synchronize do
        cleanup_if_due!
        total = @db.get_first_value("SELECT COUNT(*) FROM visits WHERE #{where}", params)
        page = page_number(filters["page"], total)
        limit = export ? EXPORT_LIMIT : PAGE_SIZE
        offset = export ? 0 : (page - 1) * PAGE_SIZE
        rows = @db.execute("SELECT * FROM visits WHERE #{where} ORDER BY occurred_at DESC, id DESC LIMIT ? OFFSET ?", params + [limit, offset])
        { rows: rows, total: total, page: page, pages: [(total.to_f / PAGE_SIZE).ceil, 1].max }
      end
    end

    def audit_events(page: 1)
      @mutex.synchronize do
        cleanup_if_due!
        total = @db.get_first_value("SELECT COUNT(*) FROM audit_events")
        current = page_number(page, total)
        rows = @db.execute("SELECT * FROM audit_events ORDER BY occurred_at DESC, id DESC LIMIT ? OFFSET ?", [PAGE_SIZE, (current - 1) * PAGE_SIZE])
        { rows: rows, total: total, page: current, pages: [(total.to_f / PAGE_SIZE).ceil, 1].max }
      end
    end

    def overview(days: 7)
      days = [7, 30, 90].include?(days) ? days : 7
      today = @clock.call.getlocal(TIME_OFFSET).to_date
      start = Time.new(today.year, today.month, today.day, 0, 0, 0, TIME_OFFSET).to_i - (days - 1) * 86_400
      @mutex.synchronize do
        cleanup_if_due!
        summary = @db.get_first_row(<<~SQL, [start])
          SELECT COUNT(*) AS views, COUNT(DISTINCT ip) AS unique_ips,
            COALESCE(SUM(status >= 400), 0) AS errors, COALESCE(SUM(bot), 0) AS bots
          FROM visits WHERE occurred_at >= ?
        SQL
        daily = @db.execute("SELECT date(occurred_at, 'unixepoch', '+8 hours') AS day, COUNT(*) AS views FROM visits WHERE occurred_at >= ? GROUP BY day", [start])
        counts = daily.to_h { |row| [row["day"], row["views"]] }
        trend = days.times.map { |i| day = (today - days + i + 1).iso8601; { "day" => day, "views" => counts.fetch(day, 0) } }
        top_pages = @db.execute("SELECT path, COUNT(*) AS views, COUNT(DISTINCT ip) AS unique_ips FROM visits WHERE occurred_at >= ? GROUP BY path ORDER BY views DESC, path LIMIT 8", [start])
        recent = @db.execute("SELECT * FROM visits ORDER BY occurred_at DESC, id DESC LIMIT 6")
        { summary: summary, trend: trend, top_pages: top_pages, recent: recent, days: days }
      end
    end

    def clear_visits
      @mutex.synchronize do
        @db.execute("DELETE FROM visits")
        @db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
      end
    end

    def close
      @mutex.synchronize { @db.close }
    end

    private

    def normalize_allowed_ip(value)
      text = value.to_s
      raise ArgumentError, "invalid_ip" if text.match?(/[[:cntrl:]]/)

      ClientAddress.normalize_ip(text.strip) || raise(ArgumentError, "invalid_ip")
    end

    def cleanup_if_due!
      cleanup! if @clock.call.to_i - @last_cleanup >= 3600
    end

    def cleanup!
      cutoff = @clock.call.to_i - @settings.fetch("retention_days").to_i * 86_400
      @db.execute("DELETE FROM visits WHERE occurred_at < ?", [cutoff])
      @db.execute("DELETE FROM audit_events WHERE occurred_at < ?", [cutoff])
      @last_cleanup = @clock.call.to_i
    end

    def page_number(value, total)
      [[value.to_i, 1].max, [(total.to_f / PAGE_SIZE).ceil, 1].max].min
    end

    def visit_conditions(filters)
      clauses = ["1 = 1"]
      params = []
      %w[ip path].each do |key|
        value = filters[key].to_s.strip
        next if value.empty?

        clauses << "instr(#{key}, ?) > 0"
        params << value.slice(0, 2048)
      end
      %w[from to].each do |key|
        next if filters[key].to_s.empty?

        date = Date.iso8601(filters[key])
        date += 1 if key == "to"
        clauses << "occurred_at #{key == 'from' ? '>=' : '<'} ?"
        params << Time.new(date.year, date.month, date.day, 0, 0, 0, TIME_OFFSET).to_i
      end
      if %w[2 3 4 5].include?(filters["status"])
        clauses << "status >= ? AND status < ?"
        params.concat([filters["status"].to_i * 100, (filters["status"].to_i + 1) * 100])
      end
      if %w[0 1].include?(filters["bot"])
        clauses << "bot = ?"
        params << filters["bot"].to_i
      end
      [clauses.join(" AND "), params]
    end
  end
end
