# LyraZeta.github.io

个人网站源码，采用分支隔离维护两种部署方式：

| 分支 | 用途 | 入口 | 是否启用后端 |
| --- | --- | --- | --- |
| `main` / `static-site` | GitHub Pages 静态站、纯静态模板 | GitHub Pages / Jekyll | 否 |
| `dynamic-site` | 个人服务器动态站 | `bin/build-dynamic`、`bin/serve-dynamic`、`server/` | 是 |

如果只想使用静态模板，请使用 `main` 或 `static-site` 分支。当前 `dynamic-site` 分支包含后端、后台面板、Nginx/systemd 部署模板和后端测试。

默认 `_config.yml` 仍关闭后端，确保本分支执行静态构建时也不会加载后端 API。服务器部署时叠加 `_config.server.yml`，页面才会加载后端 API 脚本。

## 目录结构

```text
_posts/                  Jekyll 文章源文件，两种部署共用
_layouts/、_includes/     Jekyll 页面模板，两种部署共用
css/、js/、images/        前端静态资源
server/                  个人服务器动态站后端，不进入 GitHub Pages 产物
server/data/*.example.yml 后端状态文件示例
server/data/*.yml         服务器本地状态文件，不提交
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
bin/serve-dynamic
```

本机访问使用 `http://127.0.0.1:4000`。服务器公网访问使用：

```bash
ADMIN_PASSWORD=你的强密码 BIND=0.0.0.0 PORT=4000 bin/serve-dynamic
```

等价便捷入口：

```bash
ADMIN_PASSWORD=你的强密码 PORT=4000 bin/serve-public
```

更多说明见 [docs/deployment/README.md](docs/deployment/README.md)。

如果 `lyrazeta.space` 上“已保护”文章仍能直接访问，说明公网 Nginx 没有经过 Ruby 后端。按 [Nginx 反向代理配置](docs/deployment/nginx-reverse-proxy.md) 修改。
