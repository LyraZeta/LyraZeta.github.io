# frozen_string_literal: true

require "cgi"
require "erb"
require "uri"

require_relative "activity_store"
require_relative "protection_store"

module LyraSite
  class AdminView
    ROOT = File.expand_path("../../views/admin", __dir__)
    NAVIGATION = [
      ["overview", "/admin", "访问概览", "chart-no-axes-combined"],
      ["posts", "/admin/posts", "文章管理", "files"],
      ["visits", "/admin/visits", "访问日志", "globe"],
      ["audit", "/admin/audit", "操作审计", "shield-check"],
      ["settings", "/admin/settings", "设置", "settings"]
    ].freeze
    ACTIONS = {
      "login" => "管理员登录", "login_failed" => "登录失败", "logout" => "退出登录",
      "protect" => "设置文章密码", "unprotect" => "取消文章保护", "settings" => "更新日志设置",
      "clear_visits" => "清空访问日志", "export" => "导出访问日志"
    }.freeze

    def initialize(view:, **data)
      @view = view
      data.each { |key, value| instance_variable_set("@#{key}", value) }
    end

    def render
      @content = template(@view)
      template("layout")
    end

    private

    def template(name)
      ERB.new(File.read(File.join(ROOT, "#{name}.erb"), encoding: "UTF-8"), trim_mode: "-").result(binding)
    end

    def e(value)
      CGI.escapeHTML(ProtectionStore.utf8(value))
    end

    def icon(name)
      %(<svg class="icon" aria-hidden="true"><use href="/admin/assets/icons.svg##{e(name)}"></use></svg>)
    end

    def csrf_field
      %(<input type="hidden" name="csrf_token" value="#{e(@csrf)}">)
    end

    def number(value)
      value.to_i.to_s.reverse.scan(/.{1,3}/).join(",").reverse
    end

    def timestamp(value)
      Time.at(value.to_i).getlocal(ActivityStore::TIME_OFFSET).strftime("%m-%d %H:%M:%S")
    end

    def link_to(path, updates = {})
      values = (@filters || {}).merge(updates).reject { |_, value| value.to_s.empty? }
      query = URI.encode_www_form(values)
      e(query.empty? ? path : "#{path}?#{query}")
    end

    def selected(value, expected)
      value.to_s == expected.to_s ? "selected" : ""
    end

    def pagination(result, path)
      previous = result[:page] > 1 ? %(<a class="icon-button" href="#{link_to(path, 'page' => result[:page] - 1)}" aria-label="上一页" title="上一页">#{icon('chevron-left')}</a>) : %(<button class="icon-button" disabled aria-label="上一页">#{icon('chevron-left')}</button>)
      following = result[:page] < result[:pages] ? %(<a class="icon-button" href="#{link_to(path, 'page' => result[:page] + 1)}" aria-label="下一页" title="下一页">#{icon('chevron-right')}</a>) : %(<button class="icon-button" disabled aria-label="下一页">#{icon('chevron-right')}</button>)
      %(<div class="pagination"><span>共 #{number(result[:total])} 条</span><div>#{previous}<span>#{result[:page]} / #{result[:pages]}</span>#{following}</div></div>)
    end

    def status(code)
      %(<span class="status #{code.to_i >= 400 ? 'danger' : 'neutral'}">#{e(code)}</span>)
    end
  end
end
