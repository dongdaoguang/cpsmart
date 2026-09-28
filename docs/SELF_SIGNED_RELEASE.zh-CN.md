# 固定自签名发布

[English](SELF_SIGNED_RELEASE.md) | **简体中文**

在没有 Apple Developer ID 时，cpsmart 使用一张由发布者长期保管的固定自签名证书来保持代码身份。证书只由发布者创建；普通用户不需要创建、安装或信任这张证书。

固定证书不能替代 Developer ID，也不能通过 Apple 公证或消除 Gatekeeper 的首次打开提示。它的用途是让不同版本具有稳定的指定要求（Designated Requirement），从而让 macOS 有条件把更新后的 cpsmart 认作已经授权过的同一应用。

## 创建发布身份

只在指定的发布 Mac 上执行一次：

1. 打开“钥匙串访问”。
2. 选择“钥匙串访问 → 证书助理 → 创建证书”。
3. 名称填写 `cpsmart Release Signing`。
4. 身份类型选择“自签名根证书（Self Signed Root）”。
5. 证书类型选择“代码签名（Code Signing）”。
6. 勾选“让我覆盖默认值（Let me override defaults）”。
7. 使用唯一序列号，有效期建议设置为 3650 天；其余项目保持默认。
8. 保存到当前用户的“登录”钥匙串。
9. 在“我的证书”中展开证书，确认下方存在对应私钥。
10. 双击证书并展开“信任”，只把“代码签名”设为“始终信任”，其他用途保持默认。

不要重新创建同名证书。名称相同不代表身份相同，只有原证书及其私钥才能延续代码身份。

## 备份和分享

在“钥匙串访问”的“我的证书”中选中 `cpsmart Release Signing`，导出为包含私钥的 `.p12` 文件，并设置独立的强密码。

- `.p12` 和密码必须通过两个不同的安全渠道交给发布协作者。
- 不得把 `.p12`、密码、私钥或明文导出文件提交到 Git、GitHub Release、网盘公开链接或聊天群。
- 至少保留一份离线加密备份。丢失私钥后无法通过创建同名证书恢复身份。
- 获得 `.p12` 的人可以制作被系统视为官方 cpsmart 的包，因此应按发布权限管理。

协作者导入时运行：

```bash
bash Scripts/import_signing_identity.sh /安全路径/cpsmart-release-signing.p12
```

密码由 macOS 的安全对话框读取，不写入命令历史或仓库。脚本会将该证书设为仅代码签名可信；如果 macOS 要求钥匙串密码或 Touch ID，协作者需要确认一次。导入完成后应在“钥匙串访问 → 我的证书”中确认同时存在证书和私钥。

## 生成固定自签名包

```bash
bash Scripts/build_dmg.sh --self-signed \
  --sign-identity "cpsmart Release Signing"
```

该模式会启用 Hardened Runtime、明确关闭不适用于自签名证书的 Apple 时间戳服务，并拒绝带 `cdhash` 的版本绑定身份。它不会提交 Apple 公证。

本地开发和普通测试仍使用：

```bash
bash Scripts/build_dmg.sh --local
```

只有准备交给用户的版本才使用固定发布身份。

## 首次迁移和升级验证

从临时签名版本迁移到固定证书时，已有用户预计需要最后重新授予一次辅助功能权限。后续升级不能主动重置权限；“清除旧记录”只能在自动粘贴确实失效时使用。

正式发布前至少用同一证书制作两个不同 Build Number 的安装包：

1. 安装第一个包，在系统设置中授予辅助功能权限并确认自动粘贴成功。
2. 完全退出 cpsmart，用第二个包覆盖 `/Applications/cpsmart.app`。
3. 重新启动，不清除权限，确认系统设置中的开关仍存在且自动粘贴成功。
4. 分别在主屏和副屏完成 [多屏幕与输入事件测试清单](MULTI_DISPLAY_TESTING.zh-CN.md) 中的安装包交互测试。

如果第二个版本失去权限，停止发布并比较两个包的指定要求；不能用“每次更新后重置权限”掩盖身份不稳定。

## 将来切换 Developer ID

Developer ID 和当前自签名证书是两个不同身份。将来首次切换时，用户仍可能需要重新授权一次；之后应始终使用同一个 Developer ID 身份并完成 Apple 公证。
