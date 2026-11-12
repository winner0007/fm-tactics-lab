# Mac 应用包与签名

当前交付 `FM Tactics Lab 0.7.0.app`，面向 Apple Silicon、macOS 14+。直接打开应用即可，不需要安装 Python、Homebrew、命令行工具或额外运行库，也不需要管理员安装步骤。存档读取组件已放在应用包内；FM 游戏仍需用户自行安装。

应用把数据写到当前用户的 `~/Library/Application Support/FM Tactics Lab Mac/`，不要求关闭 SIP，也不要求授予“完全磁盘访问权限”。读取受保护目录或外置磁盘时，macOS 仍可能显示正常的文件访问提示；这与安装权限不同。

## 没有 Apple 开发者账号时

本版使用本机临时签名（ad hoc），没有 Developer ID，也没有完成苹果公证。在本机构建的应用可直接运行，但通过网络下载、带隔离标记的副本可能被 Gatekeeper 拦截，**不能保证所有 Mac 下载后都无提示打开**。临时签名仅用于校验包内代码完整性，不是苹果对开发者身份的认证。

如果以后要向其他玩家分发默认可验证的下载包，需要 Apple Developer Program 中的 Developer ID 签名和公证流程。苹果说明见 [Developer ID](https://developer.apple.com/developer-id/) 与 [macOS 软件公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。届时还需重新验证加载本机 FM 插件及内置读取组件，不能只对现有 ZIP 换个签名标签。

## 维护发布包

`bash macos/scripts/build.sh` 构建原生界面、两个引擎辅助进程和独立存档读取组件，再进行本机签名。构建需要 Command Line Tools 和 Python 3.11+；这些要求只针对开发者。

交付前检查深层签名、动态库依赖、移出仓库后的启动和存档读取。ZIP 使用 `ditto` 保留应用包结构，附 SHA-256；校验值用来发现损坏，不代替 Developer ID 身份认证。包内不含 FM 引擎、游戏资源、用户存档或开发测试数据。

`dist/` 只保留当前版本。更新前退出旧应用；用户方案和历史实验保存在独立数据目录，清理旧应用不会删除它们。新格式方案不要交给旧应用编辑。

0.7.0 已验证深层签名，包内 6 个 Mach-O 文件没有开发机绝对路径动态库依赖；ZIP 解压到仓库之外后，应用成功导入新存档的 24 队、502 人和 552 场赛程，原版宿主完成同种子比赛及四次临场切换，结果与构建目录一致。这些是本机打包验证，不是苹果公证或其他 Mac 的实测结论。
