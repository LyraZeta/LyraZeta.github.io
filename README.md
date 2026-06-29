# LyraZeta.github.io

个人静态网站模板，基于 Jekyll 构建并部署到 GitHub Pages。

本分支是纯静态站版本，适合直接作为 GitHub Pages 个人网站或博客模板使用。动态后端、后台面板、文章加密服务和服务器部署文件不放在本分支；需要后端功能请使用 `dynamic-site` 分支。

## 分支说明

| 分支 | 用途 | 是否包含后端 |
| --- | --- | --- |
| `main` | GitHub Pages 静态网页部署分支 | 否 |
| `static-site` | 静态模板备份分支 | 否 |
| `dynamic-site` | 个人服务器动态网站分支 | 是 |

## 目录结构

```text
_posts/               文章源文件
_layouts/             页面布局
_includes/            公共模板片段
css/                  样式文件
js/                   前端脚本
images/               图片资源
index.html            首页
archive.html          归档页
tags.html             标签页
about.md              关于页
support.md            支持页
```

## 本地预览

```bash
bundle install
bundle exec jekyll serve
```

默认访问地址：

```text
http://127.0.0.1:4000
```

## 静态构建

```bash
bundle exec jekyll build --config _config.yml
```

构建结果默认输出到 `_site/`。该目录是生成产物，不需要提交。

## 写文章

在 `_posts/` 下新增 Markdown 文件，文件名使用 Jekyll 标准格式：

```text
YYYY-MM-DD-title.md
```

建议文件名避免空格和特殊标点，使用连字符分隔英文词。示例：

```text
2026-06-25-阿丘科技-AI-Agent.md
```

文章 front matter 示例：

```yaml
---
layout: post
title: "文章标题"
date: 2026-06-25
description: "文章摘要"
tag: 标签
math: true
---
```

如果文章不需要公式渲染，可以省略 `math: true`。

## GitHub Pages

本仓库的 GitHub Actions 会在推送到 `main` 后构建并部署静态页面。只做静态网站时，不需要配置服务器、后端服务或数据库。
