# WinSCP FTP/FTPS 站点迁移

依据 2026-11-05 核对的官方 [协议枚举](https://github.com/winscp/winscp/blob/master/source/core/SessionData.h)、[INI 读取与默认值](https://github.com/winscp/winscp/blob/master/source/core/SessionData.cpp)、[原始设置文档](https://winscp.net/eng/docs/rawsettings) 实现。认证命令顺序使用 libcurl 的 [FTPSSLAUTH](https://curl.se/libcurl/c/CURLOPT_FTPSSLAUTH.html)；不改变证书校验和 TLS 1.2 最低要求。

| INI 设置 | MacSCP 行为 |
| --- | --- |
| FSProtocol=5，Ftps=0 或缺省 | 普通 FTP，缺省端口 21；预览提示无加密 |
| Ftps=1 | 隐式 FTPS，缺省端口 990 |
| Ftps=2 | 显式 FTPS，AUTH SSL 优先，仍要求 TLS 1.2 或更新 |
| Ftps=3 | 显式 FTPS，AUTH TLS 优先 |
| PortNumber | 保留显式配置或 Default Settings 中继承的端口 |
| Timeout | 保留 1–600 秒连接/响应超时；缺省 15 秒 |
| FtpUseMlsd=on/0 | 仅 MLSD，不自动退回 LIST |
| FtpUseMlsd=off/1 | 直接 LIST |
| FtpUseMlsd=auto/2 或缺省 | MLSD；仅服务器明确不支持时退回 LIST |
| HostName、UserName、RemoteDirectory | 保留，支持转义 Unicode、相对目录和特殊字符 |
| LocalDirectory | 可用 Mac 路径保留；Windows 路径在预览提示重新选择 |
| 密码、信任缓存、脚本 | 不迁移密码或信任例外，不执行脚本；依赖 FTP 登录后命令的行阻止导入 |

默认设置会先合并，再由单个站点覆盖；重复或歧义字段不能导入。不同协议的相同用户、主机和端口分别保存。FTP 导入后仅浏览和下载，非原子写入必须在登录设置中明确开启；更新旧站点时预览会显示这一变化。

目前明确阻止的配置包括主动 FTP、ACCT、代理/SSH 隧道、客户端证书、指定证书指纹、非 UTF-8、指定 PASV 返回地址、强制 LIST -a、未支持的 TLS 范围和禁用会话复用。它们仍属待实现范围；不能静默忽略后标为完整迁移。

登录窗口的“FTP 高级设置…”可修改列表方式、连接超时及显式认证优先顺序。普通 FTP 无加密；隐式 FTPS 不使用 AUTH 命令。显式 FTPS 的认证命令会按 libcurl 的顺序尝试，始终要求加密成功，不回退到明文。

WinSCP 的超时会提供继续等待/中止交互；MacSCP 当前在超时后结束本次操作，可手动重试。预览及高级设置明确说明这一区别，超时值同时作用于原生连接及 FTP 命令响应等待。
