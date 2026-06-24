# Deployment Modes

本仓库保存两类部署方式，但默认分工不同：

| 类别 | 代码范围 | 构建配置 | 部署目标 |
| --- | --- | --- | --- |
| 静态站 | Jekyll 页面、文章、样式、图片 | `_config.yml` + `_config.github-pages.yml` | GitHub Pages |
| 动态站 | 静态站 + `server/` 后端 API | `_config.yml` + `_config.server.yml` | 个人服务器 |

关键原则：

1. `_config.yml` 是公共配置，默认 `backend.enabled: false`。
2. `_config.github-pages.yml` 专用于 GitHub Pages，不加载后端 API。
3. `_config.server.yml` 专用于个人服务器，启用后端 API 脚本。
4. `server/`、`deploy/`、`test/`、`docs/`、`bin/` 都被 Jekyll `exclude` 排除，不会被发布到静态站产物里。

详细步骤：

- [GitHub Pages 静态部署](github-pages-static.md)
- [个人服务器动态部署](server-dynamic.md)
- [Nginx 反向代理配置](nginx-reverse-proxy.md)
