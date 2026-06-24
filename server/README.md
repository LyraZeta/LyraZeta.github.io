# Server Backend

`server/` 是个人服务器动态站专用目录，GitHub Pages 静态部署不会使用这里的代码。

当前职责：

- 服务 Jekyll 构建产物 `_site/`。
- 提供 `/api/health` 健康检查。
- 提供 `/api/posts` 文章元数据接口。

启动前先使用动态配置构建静态页面：

```bash
bin/build-dynamic
ruby server/app.rb
```

推荐直接使用：

```bash
ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

如果需要从公网直接访问：

```bash
ADMIN_PASSWORD=你的强密码 PORT=4000 bin/serve-public
```

后台入口：

```text
http://127.0.0.1:4000/admin
```

默认管理员用户名是 `admin`，可用 `ADMIN_USERNAME` 覆盖。必须设置 `ADMIN_PASSWORD`，否则后台不会启用。
