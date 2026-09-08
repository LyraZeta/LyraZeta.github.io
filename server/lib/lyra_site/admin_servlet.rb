# frozen_string_literal: true

require "csv"
require "webrick"

require_relative "admin_session"
require_relative "admin_view"

module LyraSite
  class AdminServlet < WEBrick::HTTPServlet::AbstractServlet
    ASSETS = { "admin.css" => "text/css", "admin.js" => "text/javascript", "icons.svg" => "image/svg+xml" }.freeze
    TITLES = { "overview" => "访问概览", "posts" => "文章管理", "visits" => "访问日志", "audit" => "操作审计", "settings" => "设置", "login" => "后台登录" }.freeze
    NOTICES = { "protected" => "文章访问密码已更新，旧的解锁凭证已失效。", "public" => "文章已恢复公开访问。", "saved" => "日志设置已保存。", "cleared" => "访问日志已清空。", "logout" => "已退出登录。",
                "ip_added" => "IP 已加入白名单。", "ip_removed" => "IP 已移出白名单。" }.freeze
    ALLOWLIST_ERRORS = { "invalid_ip" => "请输入单个有效的 IPv4 或 IPv6 地址，不支持网段、端口或通配符。",
                        "invalid_note" => "备注最多 120 字，不能包含换行或控制字符。",
                        "duplicate_ip" => "该 IP 已在白名单中。", "unknown_ip" => "该 IP 已不在白名单中。" }.freeze

    def initialize(server, options = {})
      super(server)
      @repository = options.fetch(:repository)
      @protection_store = options.fetch(:protection_store)
      @activity = options.fetch(:activity_store)
      @sessions = options.fetch(:admin_session)
      @address = options.fetch(:client_address)
    end

    def service(request, response)
      security_headers(response)
      super
    end

    def do_GET(request, response)
      return asset(request, response) if request.path.start_with?("/admin/assets/")
      return disabled(response) unless @sessions.enabled?

      if request.path == "/admin/login"
        return redirect(response, "/admin") if @sessions.find(request)

        return login_page(request, response)
      end

      session = authorize(request, response)
      return unless session

      @csrf = session.fetch(:csrf)
      case request.path
      when "/admin", "/admin/"
        render(response, "overview", request: request, overview: @activity.overview(days: request.query["days"].to_i),
               post_count: @repository.all.length, protected_count: @protection_store.all.length)
      when "/admin/posts"
        posts_page(request, response)
      when "/admin/visits"
        filters = visit_filters(request)
        ip_notes = @activity.allowed_ips.to_h { |entry| [entry.fetch("ip"), entry.fetch("note")] }
        render(response, "visits", request: request, filters: filters, result: @activity.visits(filters), ip_notes: ip_notes)
      when "/admin/visits.csv"
        export(request, response)
      when "/admin/audit"
        render(response, "audit", request: request, result: @activity.audit_events(page: request.query["page"]))
      when "/admin/settings"
        settings_page(request, response)
      else
        error(response, 404, "未找到后台页面。")
      end
    rescue ArgumentError
      error(response, 400, "筛选条件无效，请检查日期格式。")
    end

    def do_POST(request, response)
      return disabled(response) unless @sessions.enabled?
      return handle_login(request, response) if request.path == "/admin/login"

      session = authorize(request, response)
      return unless session
      return error(response, 403, "表单已失效，请刷新页面后重试。") unless @sessions.valid_csrf?(session, request.query["csrf_token"])
      @csrf = session.fetch(:csrf)

      case request.path
      when "/admin/logout"
        audit(request, "logout")
        @sessions.logout(request)
        set_cookie(response, AdminSession::COOKIE, "deleted", 0, request)
        redirect(response, "/admin/login?notice=logout")
      when "/admin/protections"
        update_protection(request, response)
      when "/admin/settings"
        days = request.query["retention_days"]
        @activity.update_settings(enabled: request.query["enabled"] == "1", retention_days: days)
        audit(request, "settings", "enabled=#{request.query['enabled'] == '1'}; retention_days=#{days.to_i}")
        redirect(response, "/admin/settings?notice=saved")
      when "/admin/allowlist"
        update_allowlist(request, response)
      when "/admin/visits/clear"
        return error(response, 400, "请输入 DELETE 确认清空访问日志。") unless request.query["confirmation"] == "DELETE"

        @activity.clear_visits
        audit(request, "clear_visits")
        redirect(response, "/admin/settings?notice=cleared")
      else
        error(response, 404, "未找到后台操作。")
      end
    rescue ArgumentError
      error(response, 400, "输入无效：文章密码不能为空，保留天数须为 1 到 365 的整数。")
    end

    private

    def security_headers(response)
      response["Cache-Control"] = "no-store"
      response["X-Content-Type-Options"] = "nosniff"
      response["X-Frame-Options"] = "DENY"
      response["Referrer-Policy"] = "no-referrer"
      response["X-Robots-Tag"] = "noindex, nofollow"
      response["Content-Security-Policy"] = "default-src 'none'; style-src 'self'; script-src 'self'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    end

    def asset(request, response)
      name = request.path.delete_prefix("/admin/assets/")
      return error(response, 404, "资源不存在。") unless ASSETS.key?(name)

      response["Content-Type"] = "#{ASSETS.fetch(name)}; charset=utf-8"
      response["Cache-Control"] = "public, max-age=3600"
      response.body = File.binread(File.expand_path("../../assets/#{name}", __dir__))
    end

    def authorize(request, response)
      session = @sessions.find(request)
      redirect(response, "/admin/login") unless session
      session
    end

    def handle_login(request, response)
      return error(response, 403, "登录表单已失效，请重新打开登录页面。") unless @sessions.valid_login_csrf?(request)

      result = @sessions.login(ip: @address.ip(request), username: utf8(request.query["username"]), password: utf8(request.query["password"]))
      if result == :limited
        response["Retry-After"] = AdminSession::LOGIN_WINDOW.to_s
        login_page(request, response, error: "登录尝试过多，请在 15 分钟后重试。", status: 429)
      elsif result == :invalid
        audit(request, "login_failed")
        login_page(request, response, error: "用户名或密码错误。", status: 401)
      else
        audit(request, "login")
        @sessions.logout(request)
        set_cookie(response, AdminSession::COOKIE, result, AdminSession::MAX_AGE, request)
        redirect(response, "/admin")
      end
    end

    def login_page(request, response, error: nil, status: 200)
      @csrf = @sessions.login_challenge
      set_cookie(response, AdminSession::LOGIN_COOKIE, @csrf, AdminSession::LOGIN_WINDOW, request)
      render(response, "login", request: request, error: error, status: status)
    end

    def set_cookie(response, name, value, age, request)
      parts = ["#{name}=#{value}", "Path=/admin", "Max-Age=#{age}", "HttpOnly", "SameSite=Strict"]
      parts << "Secure" if @address.secure?(request)
      response["Set-Cookie"] = parts.join("; ")
    end

    def posts_page(request, response)
      filters = post_filters(request)
      protections = @protection_store.all.to_h { |entry| [entry.fetch("url"), entry] }
      posts = @repository.all
      edit = posts.find { |post| post[:url] == utf8(request.query["edit"]) }
      query = filters["q"].to_s.downcase.strip
      posts = posts.select { |post| [post[:title], post[:category], post[:url], *post[:tags]].join(" ").downcase.include?(query) }
      posts = posts.select { |post| protections.key?(post[:url]) } if filters["state"] == "protected"
      posts = posts.reject { |post| protections.key?(post[:url]) } if filters["state"] == "public"
      collections = post_collections(posts, protections)
      collection_name = nil
      if filters.key?("tag")
        collection_name = filters["tag"]
        posts = posts.select { |post| post[:tags].include?(collection_name) }
      elsif filters["untagged"] == "1"
        collection_name = "未标记"
        posts = posts.select { |post| post[:tags].empty? }
      end
      total = posts.length
      pages = [(total.to_f / ActivityStore::PAGE_SIZE).ceil, 1].max
      page = [[filters["page"].to_i, 1].max, pages].min
      filters["page"] = page.to_s if filters.key?("page")
      render(response, "posts", request: request, filters: filters, protections: protections, edit: edit,
             collections: collections, collection_name: collection_name,
             result: { rows: posts.slice((page - 1) * ActivityStore::PAGE_SIZE, ActivityStore::PAGE_SIZE) || [], total: total, page: page, pages: pages })
    end

    def post_filters(request)
      filters = request.query.slice("q", "state", "page", "tag", "untagged")
                       .transform_values { |value| utf8(value) }.reject { |_, value| value.empty? }
      filters.delete("state") unless %w[public protected].include?(filters["state"])
      filters.delete("untagged") if filters.key?("tag") || filters["untagged"] != "1"
      filters
    end

    def settings_page(request, response, status: 200, allowlist_error: nil, allowlist_form: {})
      render(response, "settings", request: request, status: status, allowed_ips: @activity.allowed_ips,
             allowlist_error: allowlist_error, allowlist_form: allowlist_form)
    end

    def update_allowlist(request, response)
      case request.query["action"]
      when "add"
        ip = @activity.add_allowed_ip(ip: utf8(request.query["ip"]), note: utf8(request.query["note"]))
        audit(request, "allowlist_add", ip)
        notice = "ip_added"
      when "remove"
        ip = @activity.remove_allowed_ip(utf8(request.query["ip"]))
        audit(request, "allowlist_remove", ip)
        notice = "ip_removed"
      else
        return error(response, 400, "未知的白名单操作。")
      end
      redirect(response, "/admin/settings?notice=#{notice}#ip-allowlist")
    rescue ArgumentError => exception
      message = ALLOWLIST_ERRORS[exception.message]
      raise unless message

      form = request.query["action"] == "add" ? request.query.slice("ip", "note").transform_values { |value| utf8(value) } : {}
      settings_page(request, response, status: 422, allowlist_error: message, allowlist_form: form)
    end

    def post_collections(posts, protections)
      groups = posts.each_with_object({}) do |post, result|
        tags = post[:tags].empty? ? [nil] : post[:tags].uniq
        tags.each { |tag| (result[tag] ||= []) << post }
      end
      groups.sort_by { |tag, rows| [tag.nil? ? 1 : 0, -rows.length, tag.to_s] }.map do |tag, rows|
        { tag: tag, title: tag || "未标记", total: rows.length,
          protected_count: rows.count { |post| protections.key?(post[:url]) }, latest: rows.first }
      end
    end

    def update_protection(request, response)
      url = ProtectionStore.canonical_url(request.query["url"])
      post = @repository.all.find { |item| ProtectionStore.canonical_url(item.fetch(:url)) == url }
      return error(response, 404, "未找到文章。") unless post

      case request.query["action"]
      when "protect"
        @protection_store.protect(url: post[:url], title: post[:title], source_path: post[:source_path], password: utf8(request.query["password"]))
        audit(request, "protect", post[:url])
        redirect(response, "/admin/posts?#{URI.encode_www_form(post_filters(request).merge('notice' => 'protected'))}")
      when "unprotect"
        @protection_store.unprotect(url)
        audit(request, "unprotect", post[:url])
        redirect(response, "/admin/posts?#{URI.encode_www_form(post_filters(request).merge('notice' => 'public'))}")
      else
        error(response, 400, "未知的文章操作。")
      end
    end

    def visit_filters(request)
      request.query.slice("ip", "path", "from", "to", "status", "bot", "page").transform_values { |value| utf8(value) }
    end

    def export(request, response)
      result = @activity.visits(visit_filters(request), export: true)
      audit(request, "export", "rows=#{result[:rows].length}")
      response["Content-Type"] = "text/csv; charset=utf-8"
      response["Content-Disposition"] = 'attachment; filename="visits.csv"'
      response["X-Export-Total"] = result[:total].to_s
      response["X-Export-Limit"] = ActivityStore::EXPORT_LIMIT.to_s
      response.body = "\uFEFF" + CSV.generate do |csv|
        csv << %w[time_utc ip path status duration_ms referrer user_agent bot]
        result[:rows].each do |row|
          values = [Time.at(row["occurred_at"]).utc.iso8601, *row.values_at("ip", "path", "status", "duration_ms", "referrer", "user_agent", "bot")]
          csv << values.map { |value| csv_cell(value) }
        end
      end
    end

    def csv_cell(value)
      text = value.to_s
      text.match?(/\A[\s\uFEFF]*[=+@-]/) ? "'#{text}" : text
    end

    def audit(request, action, target = "")
      @activity.audit(actor: @sessions.username, ip: @address.ip(request) || "unknown", action: action, target: target)
    end

    def render(response, view, request:, status: 200, **data)
      response.status = status
      response["Content-Type"] = "text/html; charset=utf-8"
      response.body = AdminView.new(view: view, title: TITLES.fetch(view), username: @sessions.username,
                                    csrf: @csrf, notice: NOTICES[request.query["notice"]], filters: {},
                                    settings: @activity.settings, **data).render
    end

    def disabled(response)
      error(response, 503, "后台未启用，请在服务器设置 ADMIN_PASSWORD 后重启后端。")
    end

    def error(response, status, message)
      response.status = status
      response["Content-Type"] = "text/html; charset=utf-8"
      response.body = AdminView.new(view: "error", title: "请求未完成", error: message).render
    end

    def redirect(response, path)
      response.set_redirect(WEBrick::HTTPStatus::SeeOther, path)
    end

    def utf8(value)
      ProtectionStore.utf8(value)
    end
  end
end
