# 参与贡献

[English](CONTRIBUTING.md) | **简体中文**

## 开发准备

需要 macOS 13 或更高版本，以及 Apple Command Line Tools。

```bash
swift build
bash Scripts/run_tests.sh
```

安装完整 Xcode 时，测试脚本会运行 SwiftPM 的标准 XCTest 目标；只有 Command Line Tools 的环境缺少 XCTest 模块，脚本才使用兼容运行器执行同一批核心用例。

请从最新的上游 `main` 创建功能分支，不要把任务交接、聊天记录、个人计划或临时截图提交到仓库。README、架构说明、测试方案、构建与发布文档可以随代码一起维护。

## 本地化

界面文案同时维护在 `Sources/cpsmart/Resources/en.lproj/Localizable.strings` 和 `Sources/cpsmart/Resources/zh-Hans.lproj/Localizable.strings`。固定文案使用 `L10n.tr`，含 `{0}`、`{1}` 等参数的文案使用 `L10n.format`；两种语言必须保留相同的占位符。辅助功能权限说明位于 `Resources/en.lproj/InfoPlist.strings` 和 `Resources/zh-Hans.lproj/InfoPlist.strings`。功能变化时同步更新中英文文档。

## 从 fork 提交 Pull Request

1. 在 GitHub 上 fork `dongdaoguang/cpsmart`。
2. 将官方仓库设为 `upstream`，自己的 fork 设为 `origin`。
3. 从 `upstream/main` 创建分支并提交改动。
4. 推送到自己的 fork，然后向 `dongdaoguang/cpsmart:main` 发起 Pull Request。

```bash
git remote rename origin upstream
git remote add origin https://github.com/<你的账号>/cpsmart.git
git fetch upstream
git switch -c feature/<功能名> upstream/main

# 修改、测试并提交后
git push -u origin feature/<功能名>
gh pr create --repo dongdaoguang/cpsmart --base main --head <你的账号>:feature/<功能名>
```

提交 PR 前请确认：

- `swift build` 和 `bash Scripts/run_tests.sh` 通过。
- 界面或输入改动已完成[多屏幕与输入事件测试清单](docs/MULTI_DISPLAY_TESTING.zh-CN.md)中的相关检查。
- PR 中只有产品代码、测试和正式文档，没有过程文档。
- README、[中文更新日志](CHANGELOG.zh-CN.md)和版本号与行为一致。
- 不提交 `build/`、`dist/`、`.build/` 或本地证书和公证凭据。
