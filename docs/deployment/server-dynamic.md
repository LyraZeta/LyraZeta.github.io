# Personal Server Dynamic Deployment

个人服务器部署会先生成 Jekyll 静态页面，再由 Ruby 后端服务 `_site/` 并提供 `/api/*`。

## 本地启动

```bash
bundle install
ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

默认地址是 `http://127.0.0.1:4000`。如果需要对外监听：

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
ADMIN_PASSWORD=你的强密码 ruby server/app.rb
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

访问：

```text
http://127.0.0.1:4000/admin
```

后台使用 HTTP Basic Auth：

- 用户名：默认 `admin`，可用 `ADMIN_USERNAME` 覆盖。
- 密码：必须设置 `ADMIN_PASSWORD`。

示例：

```bash
ADMIN_USERNAME=lyra ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

后台当前支持：

1. 查看所有文章。
2. 为指定文章设置或更新访问密码。
3. 取消指定文章的访问保护。

保护配置保存在 `server/data/protected_posts.yml`。密码不会明文保存，会保存为 PBKDF2-SHA256 哈希。
该文件属于服务器本地状态，已经被 `.gitignore` 忽略，不应推送到公开 GitHub。仓库只保留 `server/data/protected_posts.example.yml` 作为格式示例。

注意：这是动态服务器访问保护。若同一篇文章仍然被 GitHub Pages 静态站发布，它在 GitHub Pages 域名下仍然公开。真正敏感的文章不要发布到 GitHub Pages 静态站。

## 打不开时先查这些

```bash
ss -ltnp '( sport = :4000 )'
curl http://127.0.0.1:4000/api/health
```

常见原因：

1. 没有启动 `bin/serve-dynamic` 或 `bin/serve-public`。
2. 用公网 IP 或域名访问时，服务仍然只监听 `127.0.0.1`。公网直连需要 `BIND=0.0.0.0`；如果前面有 Nginx，Ruby 后端监听 `127.0.0.1` 也可以，但 Nginx 必须反向代理到 `127.0.0.1:4000`。
3. 云服务器安全组或本机防火墙没有放行端口。
4. 域名只指向 GitHub Pages，没有指向个人服务器。
5. Nginx 直接用 `root /home/lyra/LyraZeta.github.io/_site` 服务 HTML，没有反向代理到 Ruby 后端。文章保护会被绕过。见 [Nginx 反向代理配置](nginx-reverse-proxy.md)。
