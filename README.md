# ClipShelf

ClipShelf 是一个简洁的 macOS 剪贴板历史工具，支持文字、文件和截图记录。它适合想让普通截图自动进入剪贴板，同时保留原截图文件的人。

## 功能

- 记录文字、文件和图片剪贴板历史
- 监听截图文件夹，新截图自动复制到剪贴板并加入历史
- 清空历史时只删除 ClipShelf 记录，不删除访达里的原文件
- 支持搜索、键盘选择、回车粘贴、空格预览
- 支持多选、批量删除、Command-A/C/V
- 支持自定义全局呼出快捷键
- 支持自定义取消选择快捷键
- 支持开机自启动
- 支持三种 App 图标方案

## 系统要求

- macOS 13 或更新版本

## 使用前设置

为了让截图后立即进入剪贴板，请在 macOS 截图设置里：

1. 将截图保存位置设置为 ClipShelf 设置里的同一个截图文件夹
2. 关闭右下角浮动缩略图

这样截图会继续保存为文件，同时也会自动进入 ClipShelf 和剪贴板。

## 从源码运行

```bash
swift build
```

打包成本机 App：

```bash
./script/build_app_bundle.sh
```

安装到 `~/Applications` 并启动：

```bash
./script/install_app.sh
```

## 生成下载包

```bash
./script/package_release.sh
```

生成的 zip 会放在 `release/` 目录里，可以上传到 GitHub Releases。

## 隐私说明

ClipShelf 的历史记录保存在本机：

```text
~/Library/Application Support/ClipShelf/history.json
```

项目没有服务器同步功能，剪贴板内容不会被上传。

## 协议

ClipShelf 使用 MIT License 开源。

## 注意

当前脚本使用本机临时签名，适合自己使用或源码分享。若要公开分发给更多用户，建议使用 Apple Developer ID 签名并进行 notarization，否则其他用户首次打开时可能会看到 macOS 安全提示。
