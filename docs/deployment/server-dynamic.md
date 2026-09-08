# Personal Server Dynamic Deployment

个人服务器部署会先生成 Jekyll 静态页面，再由 Ruby 后端服务 `_site/` 并提供 `/api/*`。生产环境可同时运行 Jekyll 自动构建服务，在文章、布局或前端资源变化后重新生成页面。

## 正式站状态

新版后台已于 2026-09-08 启用，公网入口为 [https://lyrazeta.space/admin](https://lyrazeta.space/admin)。当前由 Nginx 代理至 `lyrazeta-backend.service` 监听的 `127.0.0.1:4000`，原账号、文章保护配置继续使用；原 4001 临时预览已关闭。

从自己的电脑访问时请使用 HTTPS 域名。下面的 `127.0.0.1` 地址是服务器本机调试和健康检查地址，不是远程浏览器的访问入口。完整部署状态见 [管理控制台](../backend-admin.md#当前部署)。

## 本地启动

```bash
bundle install
ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

默认调试地址是 `http://127.0.0.1:4000`。正式站使用 Nginx HTTPS 代理，不需要对外开放 4000。受控调试环境中需要直接监听外部连接时可使用：

```bash
ADMIN_PASSWORD=你的强密码 BIND=0.0.0.0 PORT=4000 bin/serve-dynamic
```

等价便捷入口：

```bash
ADMIN_PASSWORD=你的强密码 PORT=4000 bin/serve-public
```

## 分步命令

```bash
bin/build-dynamic
ADMIN_PASSWORD=你的强密码 bundle exec ruby server/app.rb
```

需要在前台持续监听文件变化时，可以运行：

```bash
bin/watch-dynamic
```

该命令会先完成一次完整构建，然后持续监听源文件。它不负责启动 Ruby 后端。

## Systemd 自动构建

首次部署先根据 `server/.env.example` 创建私有 `server/.env`，填写账号密码和应用密钥，并设置 `chmod 600 server/.env`。已有文件时保留其内容。systemd 会加载该文件，命令行启动脚本不会自动加载。

后端继续使用系统级服务，自动构建器使用 `lyra` 账号自己的 systemd 服务：

```bash
sudo install -m 0644 deploy/systemd/lyrazeta-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lyrazeta-backend.service

install -Dm 0644 deploy/systemd/user/lyrazeta-builder.service \
  ~/.config/systemd/user/lyrazeta-builder.service
loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now lyrazeta-builder.service
```

`lyrazeta-backend.service` 在启动 Ruby 后端前完成一次构建。`lyrazeta-builder.service` 会等待后端健康检查成功，再使用 Jekyll 的监听功能持续更新 `_site/`。启用 linger 后，即使没有登录会话，自动构建器也会随服务器启动并保持运行。

检查两个服务及自动构建日志：

```bash
systemctl status lyrazeta-backend.service
systemctl --user status lyrazeta-builder.service
journalctl --user -u lyrazeta-builder.service -f
```

## 当前 API

```text
GET /api/health
GET /api/posts
GET /api/posts?limit=0
GET /api/posts?tag=Course
```

动态构建中：

- `backend.enabled` 为 `true`。
- 页面会加载 `/js/site-api.js`。
- 页脚文章数会从 `/api/posts?limit=0` 刷新；API 不可用时保留构建时的静态值。
- 后端源码保留在仓库 `server/` 中，但不会被 Jekyll 复制到 `_site`。

## 后台面板

正式访问：[https://lyrazeta.space/admin](https://lyrazeta.space/admin)。仅在服务器本机调试时使用：

```text
http://127.0.0.1:4000/admin
```

后台使用表单登录和服务端会话，不使用浏览器 Basic Auth 弹窗：

- 用户名：默认 `admin`，可用 `ADMIN_USERNAME` 覆盖。
- 密码：正式服务从私有 `server/.env` 的 `ADMIN_PASSWORD` 读取，不在仓库记录实际值。

账号查看和改密方法见 [登录账号维护](../backend-admin.md#登录账号维护)。

示例：

```bash
ADMIN_USERNAME=lyra ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

后台当前支持访问概览、文章搜索和密码管理、访客 IP 访问日志、CSV 导出、操作审计和日志保留策略。详细字段及设置见 [管理控制台](../backend-admin.md)。

后续升级时先执行 `bundle install` 安装锁定的后端依赖，再重启 `lyrazeta-backend.service`。已有文章保护配置自动沿用，管理员和文章访问者在需要时重新登录或解锁。新日志从新版后端启动后开始采集，不自动导入旧 Nginx 日志。

保护配置保存在 `server/data/protected_posts.yml`。密码不会明文保存，会保存为 PBKDF2-SHA256 哈希。
该文件属于服务器本地状态，已经被 `.gitignore` 忽略，不应推送到公开 GitHub。仓库只保留 `server/data/protected_posts.example.yml` 作为格式示例。

注意：这是动态服务器访问保护。若同一篇文章仍然被 GitHub Pages 静态站发布，它在 GitHub Pages 域名下仍然公开。真正敏感的文章不要发布到 GitHub Pages 静态站。

## 打不开时先查这些

```bash
ss -ltnp '( sport = :4000 )'
curl http://127.0.0.1:4000/api/health
```

常见原因：

1. 在个人电脑上误用了服务器本机地址，或仍访问已关闭的 4001 预览。改用 `https://lyrazeta.space/admin`。
2. 后端服务未运行，或 Nginx 没有反向代理到 `127.0.0.1:4000`。正式站的 Ruby 只监听本机是正常配置，先检查 `systemctl status lyrazeta-backend.service`。
3. 云服务器安全组或本机防火墙没有放行端口。
4. 域名只指向 GitHub Pages，没有指向个人服务器。
5. Nginx 直接用 `root /home/lyra/LyraZeta.github.io/_site` 服务 HTML，没有反向代理到 Ruby 后端。文章保护会被绕过。见 [Nginx 反向代理配置](nginx-reverse-proxy.md)。
6. 修改文章后页面仍是旧内容时，使用 `systemctl --user status lyrazeta-builder.service` 检查自动构建器；也可执行 `bin/build-dynamic` 进行一次手动构建。
