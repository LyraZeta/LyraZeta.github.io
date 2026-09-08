# Nginx Reverse Proxy

文章加密只在 Ruby 后端里生效。公网域名必须经过 Ruby 后端，不能让 Nginx 直接把 `_site` 里的 HTML 文件返回给用户。

正式后台已于 2026-09-08 启用，入口为 [https://lyrazeta.space/admin](https://lyrazeta.space/admin)。当前线上配置已能代理 `/admin`，后台 CSS、JS 和图标通过 `@lyrazeta_backend` 回退提供；仓库模板新增的独立 `/admin` 规则尚未安装到系统中。下面的配置步骤用于首次部署或后续更新。

判断代理是否正常：

```bash
curl -I https://lyrazeta.space/api/health
```

如果返回的是 `content-type: text/html` 或首页 HTML，说明 Nginx 没有代理到 Ruby。正确结果应是 JSON：

```json
{"status":"ok","service":"lyrazeta-site",...}
```

## 1. 准备后端环境变量

仅在首次部署且 `server/.env` 不存在时，从示例创建文件；已有配置时直接编辑，不要覆盖原密码和应用密钥。

```bash
if [ ! -f server/.env ]; then
  cp server/.env.example server/.env
fi
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
TRUSTED_PROXIES=127.0.0.1/32,::1/128
```

`server/.env`、`server/data/protected_posts.yml` 和 `server/data/*.sqlite3*` 都是服务器本地私有文件，已被 `.gitignore` 忽略，不要推送到公开仓库。密码管理见 [登录账号维护](../backend-admin.md#登录账号维护)。

## 2. 安装 systemd 服务

```bash
bundle install
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

确认模板适用于本机的域名、证书和路径后应用配置。若已有其他站点规则，先合并并保留这些规则：

```bash
sudo cp deploy/nginx/lyrazeta.space.conf /etc/nginx/sites-available/default
sudo nginx -t
sudo systemctl reload nginx
```

## 4. 公网验证

```bash
curl -I https://lyrazeta.space/api/health
curl https://lyrazeta.space/api/health
curl --location --output /dev/null --write-out '%{http_code}\n' https://lyrazeta.space/admin
curl -I https://lyrazeta.space/admin/assets/admin.css
curl https://lyrazeta.space/2025/08/一起环游世界/
```

预期：

- `/api/health` 返回 JSON。
- `/admin` 未登录时跳转到登录页，跟随跳转后返回 200；后台样式应返回 200 和 CSS 类型。
- 已保护文章返回“这篇文章需要访问密码”。
- 未保护文章正常打开。

## 重要说明

Nginx 可以直接服务公开 CSS、JS、图片等资源，但后台、HTML 页面和 RSS 必须经过 Ruby。仓库模板的 `location ^~ /admin` 将后台及其资源交给 Ruby 并关闭代理缓存；`/admin` 页面响应应保留后端的 `Cache-Control: no-store`。

保持 `X-Forwarded-For` 和 `X-Forwarded-Proto` 转发；后端只信任 `TRUSTED_PROXIES` 中的代理地址，避免伪造访客 IP。正式服务保持监听 `127.0.0.1:4000` 即可，无需额外向公网开放 4000 或 4001。
