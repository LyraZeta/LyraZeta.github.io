# Deployment Modes

本仓库通过分支保存两类部署方式：

| 分支 | 代码范围 | 构建配置 | 部署目标 |
| --- | --- | --- | --- |
| `main` / `static-site` | Jekyll 页面、文章、样式、图片 | `_config.yml` | GitHub Pages / 静态模板 |
| `dynamic-site` | 静态站 + `server/` 后端 API | `_config.yml` + `_config.server.yml` | 个人服务器 |

关键原则：

1. 静态用户优先使用 `main` 或 `static-site`，不用筛选后端文件。
2. `dynamic-site` 保留完整动态站工程。
3. `_config.yml` 是公共配置，默认 `backend.enabled: false`。
4. `_config.github-pages.yml` 专用于 GitHub Pages，不加载后端 API。
5. `_config.server.yml` 专用于个人服务器，启用后端 API 脚本。
4. `server/`、`deploy/`、`test/`、`docs/`、`bin/` 都被 Jekyll `exclude` 排除，不会被发布到静态站产物里。

详细步骤：

- [GitHub Pages 静态部署](github-pages-static.md)
- [个人服务器动态部署](server-dynamic.md)
- [Nginx 反向代理配置](nginx-reverse-proxy.md)
