# 第三方工具与数据快照

以下文件是原始发布文件的备份，供 `scan-neighbors.sh` 使用，脚本会校验新下载文件的 SHA-256：

- RealiTLScanner v0.2.3：Linux amd64 和 arm64 二进制，来自 [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner/releases/tag/v0.2.3)。其 MPL-2.0 许可证及对应版本的源代码快照也保存在本目录。
- RealityChecker v2.2.3：Linux amd64 和 arm64 发布包，来自 [V2RaySSR/RealityChecker](https://github.com/V2RaySSR/RealityChecker/releases/tag/v2.2.3)。
- `data/cdn_keywords.txt` 和 `data/hot_websites.txt`：来自 RealityChecker v2.2.3。
- `data/gfwlist.conf`：来自 [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)。
- `data/Country.mmdb`：来自 [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip)。

检测数据是固定快照，不会自动更新；地理位置、CDN 和热门域名结果可能随时间变旧。脚本从本仓库取数据，检测器仍需联网访问目标站点和 DNS，检测器本身也可能尝试访问其他网络服务。更新任何文件时须同时核对来源并更新脚本中的 SHA-256。
