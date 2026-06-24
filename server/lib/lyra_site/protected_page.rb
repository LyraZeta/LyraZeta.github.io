# frozen_string_literal: true

require "cgi"

module LyraSite
  module ProtectedPage
    module_function

    def render(response, url:, title:, error: nil)
      response.status = 200
      response["Content-Type"] = "text/html; charset=utf-8"
      response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
      response["Pragma"] = "no-cache"
      response.body = html(url: url, title: title, error: error)
    end

    def html(url:, title:, error: nil)
      escaped_url = CGI.escapeHTML(url.to_s)
      escaped_title = CGI.escapeHTML(title.to_s.empty? ? "受保护文章" : title.to_s)
      escaped_error = CGI.escapeHTML(error.to_s)

      <<~HTML
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>访问受保护文章</title>
          <style>
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #f6f8fb;
              color: #20242a;
            }
            main {
              width: min(420px, calc(100vw - 32px));
              padding: 28px;
              background: #fff;
              border: 1px solid #dfe5ee;
              border-radius: 8px;
              box-shadow: 0 12px 32px rgba(20, 35, 55, 0.08);
            }
            h1 {
              margin: 0 0 8px;
              font-size: 22px;
            }
            p {
              margin: 0 0 20px;
              color: #5f6b7a;
              line-height: 1.6;
            }
            label {
              display: block;
              margin-bottom: 8px;
              font-weight: 600;
            }
            input {
              box-sizing: border-box;
              width: 100%;
              height: 42px;
              padding: 0 12px;
              border: 1px solid #cbd5e1;
              border-radius: 6px;
              font-size: 16px;
            }
            button {
              width: 100%;
              height: 42px;
              margin-top: 16px;
              border: 0;
              border-radius: 6px;
              background: #1874cd;
              color: #fff;
              font-size: 16px;
              cursor: pointer;
            }
            .error {
              margin-bottom: 14px;
              color: #b42318;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>#{escaped_title}</h1>
            <p>这篇文章需要访问密码。</p>
            #{escaped_error.empty? ? "" : %(<div class="error">#{escaped_error}</div>)}
            <form action="/unlock" method="post">
              <input type="hidden" name="url" value="#{escaped_url}">
              <label for="password">访问密码</label>
              <input id="password" name="password" type="password" autocomplete="current-password" required autofocus>
              <button type="submit">解锁文章</button>
            </form>
          </main>
        </body>
        </html>
      HTML
    end
  end
end
