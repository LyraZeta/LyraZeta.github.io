# Deployment Modes

本仓库通过分支保存两类部署方式：

| 分支 | 代码范围 | 构建配置 | 部署目标 |
| --- | --- | --- | --- |
| `main` / `static-site` | Jekyll 页面、文章、样式、图片 | `_config.yml` | GitHub Pages / 静态模板 |
| `dynamic-site` | 静态站 + `server/` 后台、API 和访客日志 | `_config.yml` + `_config.server.yml` | 个人服务器 |

正式后台已于 2026-09-08 启用：[https://lyrazeta.space/admin](https://lyrazeta.space/admin)。远程访问使用域名，`127.0.0.1:4000` 仅用于服务器本机检查；原 4001 临时预览已关闭。账号和密码由服务器私有 `server/.env` 配置，不在文档中记录实际密码。

关键原则：

1. 静态用户优先使用 `main` 或 `static-site`，不用筛选后端文件。
2. `dynamic-site` 保留完整动态站工程。
3. `_config.yml` 是公共配置，默认 `backend.enabled: false`。
4. `_config.github-pages.yml` 专用于 GitHub Pages，不加载后端 API。
5. `_config.server.yml` 专用于个人服务器，启用后端 API 脚本。
6. `server/`、`deploy/`、`test/`、`docs/`、`bin/` 都被 Jekyll `exclude` 排除，不会被发布到静态站产物里。
7. 后台代码及对应运维文档只维护在 `dynamic-site`，不向 `main` / `static-site` 同步；服务器密钥和 SQLite 数据也不提交。

详细步骤：

- [GitHub Pages 静态部署](github-pages-static.md)
- [个人服务器动态部署](server-dynamic.md)
- [Nginx 反向代理配置](nginx-reverse-proxy.md)
- [管理控制台与账号维护](../backend-admin.md)
