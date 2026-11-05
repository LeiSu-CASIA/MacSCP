<p align="center"><img src="MacSCP/Assets/AppIcon-Transfer.png" width="112" alt="MacSCP icon"></p>
<h1 align="center">MacSCP</h1>
<p align="center">A native macOS dual-pane file transfer client · macOS 双栏文件传输客户端</p>

MacSCP 参考 Commander 双栏文件管理的操作方式，使用 Swift / AppKit 实现。支持 SFTP、FTP 和显式／隐式 FTPS，提供本地／远程文件管理、多会话和后台队列。

## 功能

- 登录表单、独立服务器会话与可选系统钥匙串保存密码。
- 双栏目录、可点击路径、目录树、筛选、排序、多选和文件右键操作。
- 文件／目录上传下载、跨服务器经本机中转、文件复制粘贴。
- 向文件夹、目录树或可写会话标签拖放；标签投放保留当前会话界面。
- 传输前确认、覆盖处理、进度与限速、暂停、取消、失败重试和普通队列恢复。
- 文本／二进制传输、文件规则、命名预设和兼容性受限的 WinSCP INI 导入。
- 同步预览、镜像、可选清理、时间戳同步及保持远程更新。
- 文本编辑、文件属性、权限、校验和及远程查找。

## 界面预览

以下截图由应用原生界面使用虚构示例数据生成。

### 双栏文件管理与后台队列

![MacSCP 双栏文件管理、可点击路径、多服务器会话及传输队列](docs/images/commander.png)

### 传输前确认与本批次设置

核对来源与目标目录，选择规则、校验和及独立限速，再加入队列。

![MacSCP 传输确认与设置](docs/images/transfer-options.png)

### 队列任务详情

查看任务端点、模式、进度、限速来源与错误信息。

![MacSCP 队列任务详情](docs/images/task-details.png)

## 构建与运行

最低部署目标为 macOS 13。需要 macOS、Apple Command Line Tools（`xcode-select --install`）、Node.js / npm；不需要完整 Xcode。Intel 与 Apple 芯片的跨平台实机兼容性尚未全面验证，构建默认使用本机架构。

```sh
npm ci --ignore-scripts
./build-macscp.sh
open build/候选.noindex/MacSCP-Next.app
```

npm 只用于取得构建时打包的 xterm.js 依赖，应用运行不需要 Node。构建采用本机临时签名，未配置 Developer ID 签名或 Apple 公证；其他电脑首次打开可能出现系统安全确认。

## 使用

打开后填写主机、用户名、端口与协议；SFTP 默认端口 22。FTP 默认只读，明确允许非原子写入后才能上传。FTPS 验证证书，不会自动降级到明文。左栏为本地，右栏为服务器；双击目录进入，点击路径段返回。F5 上传／下载，F7 新建目录，F8 删除，F9 属性；Command+C / V 复制粘贴文件，Command+Shift+C 复制路径。

公开仓库不包含个人站点、密码、SSH 私钥、用户配置或测试机器的文件。请自行配置连接，不要将凭据提交到 Issue。

## 验证

```sh
./MacSCP/check.sh
```

检查脚本编译生产模块并运行 103 组检查，包括本机 stdio SFTP、隐藏原生窗口与临时目录。完整检查需要 macOS 图形登录会话及相关系统服务；成功不代表真实服务器、Finder 手势和全部 macOS 版本都已验收。仅编译模块：

```sh
MACSCP_CHECK_COMPILE_ONLY=1 ./MacSCP/check.sh
```

更多集成脚本位于 `MacSCP/`：FTP/FTPS 测试需要 Python 测试服务依赖；SSH 网络验收需要专门的本机回环服务配置。


## 许可与贡献

本项目按 GPL-3.0-only 发布，见 [LICENSE](LICENSE)。第三方组件保留各自许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

欢迎提交可复现的问题和改进。
