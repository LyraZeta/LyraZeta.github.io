# LyraZeta.github.io

个人网站源码，采用分支隔离维护两种部署方式：

| 分支 | 用途 | 入口 | 是否启用后端 |
| --- | --- | --- | --- |
| `main` / `static-site` | GitHub Pages 静态站、纯静态模板 | GitHub Pages / Jekyll | 否 |
| `dynamic-site` | 个人服务器动态站 | `bin/build-dynamic`、`bin/serve-dynamic`、`server/` | 是 |

如果只想使用静态模板，请使用 `main` 或 `static-site` 分支。当前 `dynamic-site` 分支包含后端、后台面板、Nginx/systemd 部署模板和后端测试。

默认 `_config.yml` 仍关闭后端，确保本分支执行静态构建时也不会加载后端 API。服务器部署时叠加 `_config.server.yml`，页面才会加载后端 API 脚本。

## 正式站入口

- 网站：[https://lyrazeta.space/](https://lyrazeta.space/)
- 管理后台：[https://lyrazeta.space/admin](https://lyrazeta.space/admin)

新版后台已于 2026-09-08 在正式服务器启用。管理员账号由服务器私有文件 `server/.env` 配置，实际密码不写入仓库文档。部署状态和登录维护方法见 [管理控制台说明](docs/backend-admin.md)。

`127.0.0.1:4000` 仅用于服务器本机访问；从自己的电脑访问时使用上述 HTTPS 域名。开发期间的 `4001` 临时预览已关闭。

## 目录结构

```text
_posts/                  Jekyll 文章源文件，两种部署共用
_layouts/、_includes/     Jekyll 页面模板，两种部署共用
css/、js/、images/        前端静态资源
server/                  个人服务器动态站后端，不进入 GitHub Pages 产物
server/views/admin/      后台页面模板
server/assets/           后台专用资源，由 Ruby 服务
server/data/*.example.yml 后端状态文件示例
server/data/*.yml         服务器本地状态文件，不提交
server/data/*.sqlite3*    访问日志、审计和设置，不提交
deploy/                  服务器部署模板，不进入 GitHub Pages 产物
docs/                    部署说明，不进入 GitHub Pages 产物
bin/                     本地构建和启动脚本，不进入 GitHub Pages 产物
test/                    后端测试，不进入 GitHub Pages 产物
```

## 静态构建

```bash
bundle install
bin/build-static
```

## 动态构建与启动

```bash
bundle install
ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

本机调试使用 `http://127.0.0.1:4000`。正式站由 Nginx 提供 HTTPS 并代理到这个本机端口，不需要对外开放 4000。需要受控环境下直接调试端口时可使用：

```bash
ADMIN_PASSWORD=你的强密码 BIND=0.0.0.0 PORT=4000 bin/serve-dynamic
```

等价便捷入口：

```bash
ADMIN_PASSWORD=你的强密码 PORT=4000 bin/serve-public
```

更多说明见 [docs/deployment/README.md](docs/deployment/README.md)。

动态站管理入口为 `/admin`，支持访问趋势、访客 IP 日志及 CSV 导出、文章标签集合与密码管理、操作审计和日志保留设置。文章按标签分组浏览，集合内保留搜索、筛选和分页。见 [管理控制台说明](docs/backend-admin.md)。这些后端专用改动仅保留在 `dynamic-site`，不向 `main` / `static-site` 同步。

后台右上角可选择跟随系统、日间或夜间模式，登录页也可切换，浏览器会记住选择；后台主题与博客前台的外观设置独立。

后台「设置」可维护访客 IP 白名单，支持单个 IPv4 / IPv6 地址与备注，添加或移除立即生效。白名单仅豁免文章访问密码，不授予后台权限；默认名单为空。同一公网出口 IP 下的其他访客也会获得免密阅读权限，需谨慎授权。详见 [白名单说明](docs/backend-admin.md#访客-ip-白名单)。

检查文章保护时使用未解锁的浏览器会话，并确认访问的是动态站域名。若仍能直接看到正文，按 [Nginx 反向代理配置](docs/deployment/nginx-reverse-proxy.md) 排查代理与缓存；GitHub Pages 静态站不受动态后台的密码设置影响。
