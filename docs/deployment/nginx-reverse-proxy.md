# Nginx Reverse Proxy

文章加密只在 Ruby 后端里生效。公网域名必须经过 Ruby 后端，不能让 Nginx 直接把 `_site` 里的 HTML 文件返回给用户。

当前错误配置的典型表现：

```bash
curl -I https://lyrazeta.space/api/health
```

如果返回的是 `content-type: text/html` 或首页 HTML，说明 Nginx 没有代理到 Ruby。正确结果应是 JSON：

```json
{"status":"ok","service":"lyrazeta-site",...}
```

## 1. 准备后端环境变量

```bash
cp server/.env.example server/.env
chmod 600 server/.env
nano server/.env
```

至少要设置：

```bash
ADMIN_USERNAME=lyra
ADMIN_PASSWORD=你的强密码
APP_SECRET=一段很长的随机字符串
PORT=4000
BIND=127.0.0.1
```

`server/.env` 和 `server/data/protected_posts.yml` 都是服务器本地私有文件，已被 `.gitignore` 忽略，不要推送到公开仓库。

## 2. 安装 systemd 服务

```bash
sudo cp deploy/systemd/lyrazeta-backend.service /etc/systemd/system/lyrazeta-backend.service
sudo systemctl daemon-reload
sudo systemctl enable --now lyrazeta-backend
sudo systemctl status lyrazeta-backend
```

本机验证：

```bash
curl http://127.0.0.1:4000/api/health
curl http://127.0.0.1:4000/2025/08/一起环游世界/
```

如果该文章已在后台设为“已保护”，第二条命令应该返回密码页。

## 3. 替换 Nginx 站点配置

先备份：

```bash
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak.$(date +%Y%m%d%H%M%S)
```

应用反向代理配置：

```bash
sudo cp deploy/nginx/lyrazeta.space.conf /etc/nginx/sites-available/default
sudo nginx -t
sudo systemctl reload nginx
```

## 4. 公网验证

```bash
curl -I https://lyrazeta.space/api/health
curl https://lyrazeta.space/api/health
curl https://lyrazeta.space/2025/08/一起环游世界/
```

预期：

- `/api/health` 返回 JSON。
- 已保护文章返回“这篇文章需要访问密码”。
- 未保护文章正常打开。

## 重要说明

Nginx 可以直接服务 CSS、JS、图片等静态资源，但不要直接服务 HTML。只要 HTML 绕过 Ruby 后端，文章保护就会失效。
