# Backend Migration

这个项目仍然使用 Jekyll 生成公开页面，新增的 Ruby 后端负责服务 `_site/` 目录并提供动态 API。这样可以保留现有内容写作方式，同时为后续评论、阅读量、搜索和管理后台留出稳定边界。

两类部署方式已经分开：

- GitHub Pages 静态部署：[deployment/github-pages-static.md](deployment/github-pages-static.md)
- 个人服务器动态部署：[deployment/server-dynamic.md](deployment/server-dynamic.md)

## 本地启动

```bash
bundle install
bin/build-dynamic
ADMIN_PASSWORD=你的强密码 ruby server/app.rb
```

默认地址是 `http://127.0.0.1:4000`。需要外部访问时可以显式绑定：

```bash
BIND=0.0.0.0 PORT=4000 ruby server/app.rb
```

## API

```text
GET /api/health
GET /api/posts
GET /api/posts?limit=0
GET /api/posts?tag=Course
```

`/api/posts` 从 `_posts/` 读取 Markdown front matter，返回标题、日期、标签、分类、文章链接和摘要。前端页脚会请求 `/api/posts?limit=0` 动态刷新文章数量；如果部署在 GitHub Pages 这类纯静态环境，请求失败后会保留 Jekyll 生成的静态数量。

## 部署约束

GitHub Pages 不能运行后端进程，只适合作为静态站部署。动态部署需要支持 Ruby 进程的平台，例如 VPS、Render、Railway 或 Fly.io。部署命令可以拆成：

```bash
bundle install
bin/build-dynamic
ADMIN_PASSWORD=你的强密码 ruby server/app.rb
```

后续功能建议按顺序增加：

1. 阅读量 API 和持久化存储。
2. 评论 API、审核状态和反垃圾策略。
3. 搜索 API。
4. 更细粒度的文章发布控制，例如让 GitHub Pages 静态构建自动排除受保护文章。
