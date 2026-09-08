# Backend Architecture

项目使用 Jekyll 生成页面，由 Ruby / WEBrick 后端服务 `_site/`、处理文章访问保护并提供 API 和管理控制台。访客记录、操作审计和后台设置使用 SQLite 持久化，原有文章写作方式保持不变。

新版后台已于 2026-09-08 在 [https://lyrazeta.space/admin](https://lyrazeta.space/admin) 启用。正式服务监听 `127.0.0.1:4000`，经 Nginx HTTPS 代理访问；原 4001 临时预览已关闭。功能、当前部署和账号维护见 [管理控制台](backend-admin.md)。

两类部署方式已经分开：

- GitHub Pages 静态部署：[deployment/github-pages-static.md](deployment/github-pages-static.md)
- 个人服务器动态部署：[deployment/server-dynamic.md](deployment/server-dynamic.md)

后端代码、专用资源、测试和对应文档仅维护在 `dynamic-site`。`main` / `static-site` 保留纯静态模板。

## 模块职责

| 位置 | 职责 |
| --- | --- |
| `server/app.rb`、`application.rb` | 进程启动、依赖装配、路由和服务生命周期 |
| `admin_servlet.rb`、`admin_session.rb` | 后台控制器、登录会话、CSRF 和登录限流 |
| `server/views/admin/`、`server/assets/` | 后台页面模板、本地样式、脚本和图标 |
| `activity_store.rb`、`visit_recorder.rb`、`client_address.rb` | SQLite 日志、统计和 IP 白名单，请求采集、可信代理 IP 解析 |
| `protection_store.rb`、`access_session.rb`、`protected_static_servlet.rb` | 文章密码存储、解锁凭证和访问检查 |
| `public_content.rb`、`api_servlet.rb` | 受保护文章的首页摘要、RSS 及公开 API 过滤 |

上表仅写文件名的模块均位于 `server/lib/lyra_site/`。运行配置和数据不进入 Git：`server/.env` 保存服务配置，`protected_posts.yml` 保存文章密码哈希，`activity.sqlite3` 保存访问记录、审计、设置与 `ip_allowlist` 白名单表。

白名单由已登录管理员在「设置」维护，修改校验 CSRF 并记录审计。文章请求逐次查询当前 IP 是否获准，不因白名单签发解锁 Cookie；移除后立即恢复密码要求，之前通过文章密码取得的有效 Cookie 不受影响。`ClientAddress#visitor_ip` 在可信代理缺少有效转发链时返回空值，不使用日志用的代理地址回退结果授权。首页摘要、RSS 和公开 API 仍按公开规则过滤受保护内容，后台登录不受白名单影响。

## 本地启动

```bash
bundle install
bin/build-dynamic
ADMIN_PASSWORD=你的强密码 bundle exec ruby server/app.rb
```

默认调试地址是 `http://127.0.0.1:4000`。从个人电脑访问正式后台应使用 HTTPS 域名；受控调试环境需要直接监听外部连接时可以显式绑定：

```bash
ADMIN_PASSWORD=你的强密码 BIND=0.0.0.0 PORT=4000 bundle exec ruby server/app.rb
```

## API

```text
GET /api/health
GET /api/posts
GET /api/posts?limit=0
GET /api/posts?tag=Course
```

`/api/posts` 从 `_posts/` 读取 Markdown front matter，返回标题、日期、标签、分类、文章链接、摘要及 `protected` 状态。对受保护文章，摘要和描述为 `null`，不返回源文件路径。

动态站页脚请求 `/api/posts?limit=0` 刷新文章数量，接口不可用时保留构建时数量；GitHub Pages 静态构建关闭 `backend.enabled`，不加载后端脚本，也不请求这些 API。访客日志仅通过需登录的 `/admin` 路由查看和导出，没有公开的 IP 日志接口。

## 部署约束

GitHub Pages 不能运行后端进程，只适合作为静态站部署。动态部署需要支持 Ruby 进程的平台，例如 VPS、Render、Railway 或 Fly.io。部署命令可以拆成：

```bash
bundle install
bin/build-dynamic
ADMIN_PASSWORD=你的强密码 bundle exec ruby server/app.rb
```

已有功能包括访问概览、IP 日志筛选与导出、文章标签集合及集合内搜索和密码管理、操作审计、日志启停及保留策略。正式服务使用 systemd 加载私有环境配置，运维命令见 [动态部署](deployment/server-dynamic.md)。

尚未实现的后续功能可以按需求逐步增加：

1. 面向读者的文章阅读量展示与公开聚合接口。
2. 评论 API、审核状态和反垃圾策略。
3. 面向读者的全文搜索接口。
4. 独立的文章发布管理；如需改变静态站的发布策略，应另行修改静态分支。
