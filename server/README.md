# Server Backend

`server/` 是个人服务器动态站专用目录，GitHub Pages 静态部署不会使用这里的代码。

正式后台已启用：[https://lyrazeta.space/admin](https://lyrazeta.space/admin)。服务由 `lyrazeta-backend.service` 管理，Nginx 将 HTTPS 请求转发到 `127.0.0.1:4000`。

当前职责：

- 服务 Jekyll 构建产物 `_site/`。
- 提供 `/api/health` 健康检查。
- 提供 `/api/posts` 文章元数据接口。
- 提供 `/admin` 管理控制台：访问概览、文章保护、访客 IP 日志、操作审计和日志设置。
- 使用 SQLite 持久化访客记录，按保留策略清理。
- 后台提供跟随系统、日间和夜间三种外观选项，记住当前浏览器的选择。
- 文章管理按标签集合组织，集合内支持搜索、状态筛选、分页和密码管理；无标签文章归入「未标记」。
- 后台设置提供访客 IP 白名单管理，按可信访客的单个 IPv4 / IPv6 地址免除全部文章密码，添加及移除记录操作审计；白名单默认为空。

启动前先使用动态配置构建静态页面：

```bash
bundle install
bin/build-dynamic
ADMIN_PASSWORD=你的强密码 bundle exec ruby server/app.rb
```

推荐直接使用：

```bash
ADMIN_PASSWORD=你的强密码 bin/serve-dynamic
```

需要在后端运行期间自动应用文章和页面改动时，另开一个进程运行：

```bash
bin/watch-dynamic
```

生产服务器建议安装 `deploy/systemd/user/lyrazeta-builder.service`，由用户级 systemd 持续运行并在异常或服务器重启后自动恢复。

正式访问使用上面的 HTTPS 域名；仅在受控调试环境需要直接访问端口时使用：

```bash
ADMIN_PASSWORD=你的强密码 PORT=4000 bin/serve-public
```

本机调试入口：

```text
http://127.0.0.1:4000/admin
```

默认管理员用户名是 `admin`，可用 `ADMIN_USERNAME` 覆盖。必须设置 `ADMIN_PASSWORD`，否则后台不会启用。

正式服务从 `server/.env` 读取账号配置，采用表单登录。升级后需要重新登录。此文件不会被命令行启动脚本自动加载；手动运行时需传入环境变量。`127.0.0.1` 指浏览器所在机器，远程访问请使用正式域名；旧的 4001 临时预览服务已关闭。

实际密码只保存在服务器的私有配置中。查看和修改账号的方法见 [登录账号维护](../docs/backend-admin.md#登录账号维护)。

## 后端目录

```text
app.rb                       进程入口
lib/lyra_site/application.rb  服务装配和路由挂载
lib/lyra_site/*_servlet.rb    HTTP 控制器
lib/lyra_site/admin_session.rb 管理员会话、CSRF 和登录限流
lib/lyra_site/client_address.rb 可信代理及客户端 IP 解析
lib/lyra_site/activity_store.rb SQLite 日志、统计、设置与清理
lib/lyra_site/visit_recorder.rb 页面访问记录
lib/lyra_site/public_content.rb 受保护文章的列表摘要和 RSS 过滤
views/admin/                 后台 ERB 模板
assets/                      后台专用样式、脚本与本地图标
data/                        服务器私有运行数据
```

安装依赖后执行后端测试：

```bash
bundle install
bundle exec ruby -Iserver/lib:test -e 'Dir["test/server/*_test.rb"].sort.each { |file| require_relative file }'
```

功能及运维细节见 [管理控制台](../docs/backend-admin.md)。
