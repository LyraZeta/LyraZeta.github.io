# frozen_string_literal: true

require "cgi"
require "openssl"
require "uri"
require "webrick"

require_relative "password_hasher"

module LyraSite
  class AdminServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, options = {})
      super(server)
      @repository = options.fetch(:repository)
      @protection_store = options.fetch(:protection_store)
      @username = ENV.fetch("ADMIN_USERNAME", "admin")
      @password = ENV["ADMIN_PASSWORD"].to_s
      app_secret = ENV["APP_SECRET"].to_s
      @secret = app_secret.empty? ? @password : app_secret
    end

    def do_GET(request, response)
      case request.path
      when "/admin/login"
        render_login(response, notice: utf8(request.query["notice"]))
      when "/admin/logout"
        clear_admin_session(response)
        response.set_redirect(WEBrick::HTTPStatus::SeeOther, "/admin/login?notice=#{URI.encode_www_form_component('已退出登录')}")
      else
        return unless authorize_admin(request, response)

        render_dashboard(response, notice: utf8(request.query["notice"]))
      end
    end

    def do_POST(request, response)
      if request.path == "/admin/login"
        return forbidden(response) unless same_origin?(request)

        return handle_login(request, response)
      end

      return unless authorize_admin(request, response)
      return forbidden(response) unless same_origin?(request)

      action = utf8(request.query["action"])
      url = ProtectionStore.canonical_url(request.query["url"])
      post = @repository.all.find { |item| ProtectionStore.canonical_url(item.fetch(:url)) == url }

      case action
      when "protect"
        return redirect(response, "未找到文章") unless post

        @protection_store.protect(
          url: post.fetch(:url),
          title: post.fetch(:title),
          source_path: post.fetch(:source_path),
          password: utf8(request.query["password"])
        )
        redirect(response, "已更新访问密码")
      when "unprotect"
        @protection_store.unprotect(url)
        redirect(response, "已取消访问保护")
      else
        redirect(response, "未知操作")
      end
    rescue ArgumentError => error
      redirect(response, error.message == "password_required" ? "密码不能为空" : "操作失败")
    end

    private

    def utf8(value)
      ProtectionStore.utf8(value)
    end

    def authorize_admin(request, response)
      return admin_disabled(response) if @password.empty?

      return true if admin_session_valid?(request)

      response.set_redirect(WEBrick::HTTPStatus::SeeOther, "/admin/login")
      false
    end

    def handle_login(request, response)
      return admin_disabled(response) if @password.empty?

      user = utf8(request.query["username"])
      password = utf8(request.query["password"])

      if secure_equal?(user, @username) && secure_equal?(password, @password)
        grant_admin_session(response)
        response.set_redirect(WEBrick::HTTPStatus::SeeOther, "/admin")
      else
        render_login(response, error: "用户名或密码错误。")
      end
    end

    def secure_equal?(left, right)
      PasswordHasher.secure_compare(left.to_s, right.to_s)
    end

    def admin_session_valid?(request)
      cookie = request.cookies.find { |item| item.name == admin_cookie_name }
      return false unless cookie

      secure_equal?(cookie.value, admin_token)
    end

    def grant_admin_session(response)
      response["Set-Cookie"] = [
        "#{admin_cookie_name}=#{admin_token}",
        "Path=/admin",
        "Max-Age=#{60 * 60 * 12}",
        "HttpOnly",
        "SameSite=Lax"
      ].join("; ")
    end

    def clear_admin_session(response)
      response["Set-Cookie"] = [
        "#{admin_cookie_name}=deleted",
        "Path=/admin",
        "Max-Age=0",
        "HttpOnly",
        "SameSite=Lax"
      ].join("; ")
    end

    def admin_cookie_name
      "lyra_admin_session"
    end

    def admin_token
      OpenSSL::HMAC.hexdigest("SHA256", @secret, "admin:#{@username}:#{@password}")
    end

    def admin_disabled(response)
      response.status = 503
      response["Content-Type"] = "text/html; charset=utf-8"
      response.body = page_shell(
        title: "后台未启用",
        body: <<~HTML
          <p>请设置 <code>ADMIN_PASSWORD</code> 后重启动态服务。</p>
          <pre>ADMIN_PASSWORD=你的强密码 bin/serve-dynamic</pre>
        HTML
      )
      false
    end

    def same_origin?(request)
      origin = request["Origin"].to_s
      referer = request["Referer"].to_s
      header = origin.empty? ? referer : origin
      return true if header.empty?

      uri = URI.parse(header)
      uri.host == request.host && uri.port == request.port
    rescue URI::InvalidURIError
      false
    end

    def forbidden(response)
      response.status = 403
      response["Content-Type"] = "text/plain; charset=utf-8"
      response.body = "跨站请求已被拒绝。"
    end

    def redirect(response, notice)
      encoded_notice = URI.encode_www_form_component(utf8(notice))
      response.set_redirect(
        WEBrick::HTTPStatus::SeeOther,
        "/admin?notice=#{encoded_notice}"
      )
    end

    def render_dashboard(response, notice: nil)
      posts = @repository.all
      protections = @protection_store.all
      protected_urls = protections.to_h { |entry| [entry.fetch("url"), entry] }
      rows = posts.map { |post| post_row(post, protected_urls[post.fetch(:url)]) }.join
      notice_html = notice.to_s.empty? ? "" : %(<div class="notice">#{escape(notice)}</div>)

      response.status = 200
      response["Content-Type"] = "text/html; charset=utf-8"
      response.body = page_shell(
        title: "LyraZeta 后台",
        body: <<~HTML
          #{notice_html}
          <section class="summary">
            <span>文章 #{posts.length} 篇</span>
            <span>已保护 #{protections.length} 篇</span>
            <a class="logout" href="/admin/logout">退出登录</a>
          </section>
          <table>
            <thead>
              <tr>
                <th>文章</th>
                <th>日期</th>
                <th>状态</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              #{rows}
            </tbody>
          </table>
        HTML
      )
    end

    def render_login(response, notice: nil, error: nil)
      notice_html = notice.to_s.empty? ? "" : %(<div class="notice">#{escape(notice)}</div>)
      error_html = error.to_s.empty? ? "" : %(<div class="error">#{escape(error)}</div>)

      response.status = 200
      response["Content-Type"] = "text/html; charset=utf-8"
      response.body = page_shell(
        title: "后台登录",
        body: <<~HTML
          <section class="login-panel">
            #{notice_html}
            #{error_html}
            <form action="/admin/login" method="post">
              <label for="username">用户名</label>
              <input id="username" name="username" type="text" value="#{escape(@username)}" autocomplete="username" required>
              <label for="password">密码</label>
              <input id="password" name="password" type="password" autocomplete="current-password" required autofocus>
              <button type="submit">登录</button>
            </form>
          </section>
        HTML
      )
    end

    def post_row(post, protection)
      url = post.fetch(:url)
      protected_label = protection ? "已保护" : "公开"
      protected_class = protection ? "protected" : "public"

      <<~HTML
        <tr>
          <td>
            <strong>#{escape(post.fetch(:title))}</strong>
            <small>#{escape(url)}</small>
          </td>
          <td>#{escape(post.fetch(:date))}</td>
          <td><span class="status #{protected_class}">#{protected_label}</span></td>
          <td>
            <form action="/admin/protections" method="post">
              <input type="hidden" name="url" value="#{escape(url)}">
              <input type="password" name="password" placeholder="设置/更新访问密码" autocomplete="new-password">
              <button type="submit" name="action" value="protect">加密</button>
              <button type="submit" name="action" value="unprotect" class="secondary">取消</button>
            </form>
          </td>
        </tr>
      HTML
    end

    def page_shell(title:, body:)
      <<~HTML
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{escape(title)}</title>
          <style>
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #f6f8fb;
              color: #1f2933;
            }
            header {
              padding: 20px 32px;
              background: #102a43;
              color: #fff;
            }
            main {
              padding: 24px 32px 48px;
            }
            h1 {
              margin: 0;
              font-size: 24px;
            }
            .summary {
              display: flex;
              gap: 12px;
              margin-bottom: 16px;
            }
            .summary span,
            .notice,
            .error {
              padding: 8px 12px;
              border-radius: 6px;
            }
            .notice {
              background: #e6f4ff;
              color: #0b5cab;
            }
            .error {
              margin-bottom: 12px;
              background: #fee2e2;
              color: #991b1b;
            }
            .logout {
              display: inline-flex;
              align-items: center;
              padding: 8px 12px;
              border-radius: 6px;
              background: #334155;
              color: #fff;
              text-decoration: none;
            }
            .login-panel {
              max-width: 420px;
              padding: 24px;
              background: #fff;
              border: 1px solid #dde6f0;
              border-radius: 8px;
            }
            .login-panel form {
              display: grid;
              gap: 10px;
            }
            .login-panel input,
            .login-panel button {
              width: 100%;
              box-sizing: border-box;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              background: #fff;
              border: 1px solid #dde6f0;
            }
            th,
            td {
              padding: 12px;
              border-bottom: 1px solid #edf2f7;
              text-align: left;
              vertical-align: top;
            }
            th {
              background: #f8fafc;
              font-weight: 700;
            }
            small {
              display: block;
              margin-top: 6px;
              color: #64748b;
            }
            form {
              display: flex;
              gap: 8px;
              flex-wrap: wrap;
            }
            input {
              min-width: 220px;
              height: 34px;
              padding: 0 10px;
              border: 1px solid #cbd5e1;
              border-radius: 6px;
            }
            button {
              height: 36px;
              padding: 0 12px;
              border: 0;
              border-radius: 6px;
              background: #1874cd;
              color: #fff;
              cursor: pointer;
            }
            button.secondary {
              background: #64748b;
            }
            .status {
              display: inline-block;
              padding: 4px 8px;
              border-radius: 999px;
              font-size: 12px;
            }
            .status.protected {
              background: #fee2e2;
              color: #991b1b;
            }
            .status.public {
              background: #dcfce7;
              color: #166534;
            }
            code,
            pre {
              background: #e2e8f0;
              border-radius: 6px;
            }
            code {
              padding: 2px 4px;
            }
            pre {
              padding: 12px;
              overflow-x: auto;
            }
          </style>
        </head>
        <body>
          <header><h1>#{escape(title)}</h1></header>
          <main>#{body}</main>
        </body>
        </html>
      HTML
    end

    def escape(value)
      CGI.escapeHTML(utf8(value))
    end
  end
end
