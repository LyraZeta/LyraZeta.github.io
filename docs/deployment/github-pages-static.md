# GitHub Pages Static Deployment

GitHub Pages 只部署静态页面，不运行后端进程。

## 本地验证

```bash
bundle install
bin/build-static
```

等价命令：

```bash
bundle exec jekyll build --config _config.yml,_config.github-pages.yml --destination _site
```

## GitHub Actions

静态部署入口是 `.github/workflows/deploy_pages.yml`。该 workflow 只执行静态构建并上传 `_site`，不会启动 `server/app.rb`。

静态构建中：

- `backend.enabled` 为 `false`。
- 页面不会加载 `/js/site-api.js`。
- 页脚文章数使用 Jekyll 构建时生成的静态值。
- `server/`、`test/`、`docs/`、`bin/` 不会进入 `_site`。
