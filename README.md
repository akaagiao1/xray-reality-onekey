# Xray VLESS + REALITY 一键脚本（支持 Surge 和 Quantumult X）

服务端用 Xray-core，协议是 **VLESS / TCP + REALITY + xtls-rprx-vision**，默认使用 443 端口；自动安装会从扫描结果中挑选符合条件的邻居域名作为 REALITY 的目标站和 SNI。输出 Surge `[Proxy]` 节点行、Quantumult X（QuanX）`[server_local]` 节点行、通用 `vless://` 链接和二维码（终端打印一份，`/root/xray-reality-client.png` 存一份，手机扫码即导入）。

## Surge 快速使用

如果 VPS 上已经装好了节点，使用 root 登录 VPS 后运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) show
```

复制输出中 **Surge** 下的整行，粘贴到 Surge 配置的 `[Proxy]` 段，然后在 Surge 中选择该节点。客户端配置也保存在 VPS 的 `/root/xray-reality-client.txt`；文件包含连接凭据，请勿公开分享。

还没安装节点？继续阅读下面的“推荐流程：先扫描，后安装”。该配置需要 Surge iOS **6.0.0+** 或 Surge Mac **6.12.0+**；完整示例和参数说明见下方“Surge 配置”。

## 环境与依赖

先装好依赖（缺了脚本也会自动装，Debian/Ubuntu 走 apt，Alpine 走 apk，会先 `apk update`，精简版 Alpine 出厂没有仓库索引）：

```bash
# Debian / Ubuntu
apt update && apt install -y curl python3

# Alpine
apk update && apk add --no-cache bash curl python3 gcompat
```

支持的环境：

- Debian 11/12/13
- Ubuntu 20.04 / 22.04 / 24.04
- Alpine Linux（OpenRC；精简版没预装 OpenRC 也能装，脚本会先装上再检测）
- root 或可 sudo 的用户
- QuanX **1.5.5+** 才支持 VLESS Reality + Vision，低版本请先升级 QuanX
- Surge **iOS 6.0.0+ / Mac 6.12.0+** 支持 VLESS + REALITY + Vision；请确认客户端版本支持

## 推荐流程：先扫描，后安装

**不要直接用默认域名装。** 先扫 VPS 所在网段，挑一个冷门的邻居域名做 dest/SNI，再装节点。两条路：

```bash
# 路 1：全自动——扫完直接装（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/auto-reality.sh)

# 路 2：手动两步——先扫，挑一个，再装
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/scan-neighbors.sh)
REALITY_SNI=挑到的域名 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) install
```

路 1 扫完没有合格域名会直接停下，不会退回默认域名装；机器上已有 Xray 也会停下，以免覆盖现有节点。

## 三个脚本怎么选

| 脚本 | 干什么 | 什么时候用 |
| --- | --- | --- |
| `auto-reality.sh` | 扫描邻居网段 → 筛选推荐域名 → 直接装好节点 | 新机器，想一步到位 |
| `scan-neighbors.sh` | 只扫描和筛选，输出 `file.csv` + 推荐域名 | 只想挑域名，或先看一眼再决定 |
| `reality` | 安装 / 查看 / 扫描重装 / 换端口 / 更新 / 卸载节点 | 直接装（默认域名），或管理已有节点 |

三个脚本都是一行命令跑，不用先下载。`reality` 有终端时进菜单，无终端（管道）时直接安装。

## 扫描并自动安装

在新 VPS 的 root 终端运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/auto-reality.sh)
```

脚本会做三件事：

1. **扫描**本机公网 IPv4 所在 `/23` 的 443 端口，检测候选域名；
2. **筛选**出合格结果里握手时间最低的域名作为 SNI/dest；
3. **安装** Xray REALITY：装依赖、配置 Xray 和服务、调整防火墙和 BBR。

两种情况会直接停下，不装：

- **机器上已有 Xray**（程序、配置或服务任一存在）——怕覆盖现有节点。先卸载再装：`bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) uninstall --purge`（彻底删，含配置；不加 `--purge` 只卸程序、保留配置）。
- **没有合格的推荐域名**——不会退回默认域名装。换个网段再扫，或用已验证的域名手动装（见下节）。

已经扫过、有 `file.csv` 的，可以跳过扫描：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/auto-reality.sh) --csv file.csv
```

`--csv` 后面必须是**已存在、可读**的扫描结果文件；文件不存在会直接报错，不会当成参数错误含糊过去。

注意：只扫描有权扫描的网段，扫描器上游建议在本地扫描，VPS 扫描可能被标记。推荐只是基于检测时的数据，无法保证同 ASN、稳定或避免封锁。

## 手动两步：先扫，再装

已经有个想用的域名（刚筛出来的冷门域名，或自己验证过的），直接装：

```bash
REALITY_SNI=你的邻居域名 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) install
```

装完想换域名，不用重装：`bash reality reconfig`，改完旧的 QuanX 行 / 链接 / 二维码全部作废，脚本会重新输出新的。

## 找邻居域名（一键扫）

想找跟 VPS 同网段的冷门域名做 dest，不用手动装两个工具，跑这个就行（`scan-neighbors.sh`，也在本仓库）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/scan-neighbors.sh)
```

它会自动探测公网 IP，扫描所在 `/23`（512 个地址，443 端口，100 线程，5 秒超时），把结果写入 `file.csv`，核对证书域名当前解析是否包含扫描到的 IP，再交给 RealityChecker 检测。支持新版扫描器的 CSV 格式；需要 `curl` 和 `python3`，工具不存在时从本仓库 `vendor/` 下载并校验 SHA-256；已有的可执行文件会直接复用。下载失败或 SHA-256 不匹配时自动重试并切换到仓库备用地址，不匹配的文件不会执行。检测用数据也是仓库中的固定快照，不会自动更新。RealityChecker 的检测结果包括不匹配的域名，需结合解析结果判断。脚本会从检测输出中过滤上游的广告行，并在最后推荐最多 3 个域名：检测基础条件通过、状态码 200、未识别为 CDN 和热门站点、证书剩余至少 14 天，最终域名与扫描证书域名一致且当前解析包含扫描 IP；按握手时间从低到高排序。没有符合条件的域名时不会强行推荐。

输出文件：

- `file.csv`：扫描原始结果，11 列（`IP,ORIGIN,TLS,ALPN,CURVE,CERT_LENGTH,CERT_SIGNATURE,CERT_PUBLICKEY,CERT_DOMAIN,CERT_ISSUER,GEO_CODE`），第 9 列是证书域名；
- 终端最后打印的**推荐 1–3**：按握手延迟排序，挑个冷门的用（`REALITY_SNI=域名` 装节点，或装完 `bash reality reconfig` 改过去）。

也可以指定：

```bash
# 指定 IP（自动换成它所在的 /23）或网段、输出文件名
bash scan-neighbors.sh 154.9.236.158  # 默认扫描所在 /23
bash scan-neighbors.sh 154.9.236.0/24 file2.csv  # 指定范围
# 使用已有结果重新检测，不重新扫描
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/scan-neighbors.sh) --csv file.csv
# 只看要执行的命令，不真扫
bash scan-neighbors.sh --dry-run 154.9.236.158
```

注意：上游建议在本地扫描，VPS 上扫描可能被标记；仅扫描获授权的目标。裸 IP 会自动换成所在的 /23；可以手动指定 /24 或其他获授权的 CIDR。扫描更多地址不保证找到更多可用域名。DNS 匹配只是当前时刻的参考，并不证明同 ASN 或保证连接稳定；如果检测器显示最终域名与扫描域名不同，需单独核对最终域名的解析。再次扫描可能覆盖 `file.csv`。

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality)
```

无终端（管道）时直接安装；有终端时进菜单，选完一项回到菜单，直到选 0 退出：

1. **查看客户端配置** — Surge 行 + QuanX 行 + vless:// 链接 + 二维码
2. **重新安装并扫描 Reality 域名** — 扫本机所在 /23 的邻居域名，用握手最快的合格域名重装，只换 dest/SNI，UUID / 密钥 / 端口不变；扫不到合格域名就停，现有节点不动
3. **更换 Reality 端口** — 只换端口，域名 / UUID / 密钥 / shortId 都不变；新端口同样过 CF 反代端口和占用检查
4. **完全卸载** — 删 Xray 程序、服务、配置、客户端文件和二维码，菜单里要输入 `yes` 才执行

安装时会问伪装域名（Reality dest/SNI）：新安装时应填写筛选出的邻居域名；如果直接回车，单独安装脚本当前会回退到 `www.amazon.com`。填了 CF 的站、或解析到 CF IP 的站会被拒绝并重问（最多 3 次）；非交互安装（管道）不提问，用环境变量 `REALITY_SNI` 指定，不指定就用默认。

也可以直接指定操作（不进菜单）：

```bash
# 查看客户端配置（Surge 行 + QuanX 行 + vless:// + 二维码，qrencode 装好后才有二维码）
bash reality show

# 扫描邻居域名并重装（只换 dest/SNI；扫不到合格域名就停）
bash reality rescan

# 只换端口（域名/密钥不变）；非交互：REALITY_PORT=24444 bash reality change-port
bash reality change-port

# 更改配置：改伪装域名 / 改端口 / 重新生成密钥（可单改可全改，旧的客户端配置作废）
bash reality reconfig
# 非交互改法：REALITY_SNI=www.bing.com REALITY_PORT=24444 REALITY_REGEN_KEYS=1 bash reality reconfig

# 只换 Xray 二进制，UUID / 密钥 / 端口全部保留
bash reality update

# 卸载程序，保留配置，重装会继续用它
bash reality uninstall

# 彻底卸载，同时删配置、客户端文件和二维码（菜单 4 同款，命令行不问确认）
bash reality uninstall --purge
```

如果服务器没有 `curl`：

```bash
# Debian / Ubuntu
apt update && apt install -y curl

# Alpine
apk update && apk add --no-cache bash curl

bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality)
```

脚本会自动完成：

- 按架构下载 Xray-core（默认最新版，失败回落到已验证的 `v26.10.31`），有 `.dgst` 就验 sha256
- 用 `xray x25519` 生成 Reality 密钥对，用 `xray uuid` / 系统随机生成 UUID，shortId 固定 16 位 hex
- 写 `/usr/local/etc/xray/config.json`，`xray -test` 校验通过才启动
- 创建并启动 systemd 或 OpenRC 服务 `xray`，开机自启
- UFW / firewalld / iptables 放行端口（尽力而为）
- 输出 Surge 和 QuanX 客户端配置并保存到 `/root/xray-reality-client.txt`，同时生成二维码：终端打印一份，PNG 存到 `/root/xray-reality-client.png`（装 `qrencode` 失败时跳过二维码，不中断安装，装好后跑 `bash reality show` 可补生成）
- 依赖已齐全时跳过包管理器安装，二次运行改配置不必再跑一遍 apt/apk

重装 / 升级时，已有配置的 UUID、私钥、端口、SNI、shortId 全部保留，不会悄悄换掉客户端配置。**要改这些，跑 `bash reality reconfig`**：改域名、改端口、重新生成密钥（新私钥/公钥 + 新 shortId）、换 UUID 都可以单改，改完旧的 QuanX 行 / 链接 / 二维码全部作废，脚本会重新输出新的。改端口、改域名同样过 Cloudflare 硬规则（CF 反代端口、CF 站直接拒绝）和端口占用检查。只换端口也可以用菜单 3 / `bash reality change-port`；想换个邻居域名可以用菜单 2 / `bash reality rescan` 扫描后重装。

自动安装通过 `REALITY_SNI` 将扫描得到的推荐域名传给安装脚本。单独运行 `reality install` 时，若没有提供域名且没有已有配置，当前实现仍会回退到 `www.amazon.com`；如需使用邻居域名，应显式指定 `REALITY_SNI`。

## Surge 配置

安装后复制输出中的 Surge 配置行到 Surge 配置的 `[Proxy]` 段；已有节点可以运行下面的命令重新生成配置：`reconfig` 完成后也会输出更新的节点行。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) show
```

```ini
[Proxy]
Reality = vless, 服务器IP, 443, username=<UUID>, flow=xtls-rprx-vision, sni=<你的邻居域名>, reality-public-key=<公钥>, reality-short-id=<shortId>
```

上面是格式示例，使用脚本输出的真实值。Surge 的 REALITY 无需额外设置 `tls=true`，VLESS 默认支持 UDP relay；客户端使用自己的 TLS 栈。需要 Surge iOS **6.0.0+** 或 Mac **6.12.0+**，详见 [Surge VLESS 官方文档](https://manual.nssurge.com/policies/vless.html)。请保护包含 UUID、公钥和 shortId 的客户端文件，避免公开分享。

## Quantumult X 配置

安装完成后，**优先用这一行**，粘贴到 QuanX 配置的 `[server_local]`：

```ini
vless=服务器IP:443, method=none, password=<UUID>, obfs=over-tls, obfs-host=<你的邻居域名>, reality-base64-pubkey=<公钥>, reality-hex-shortid=<16位hex>, vless-flow=xtls-rprx-vision, udp-relay=true, tag=Reality-QuanX
```

不要只靠 `vless://` 链接导入：旧版解析器可能丢 `reality` 参数，节点会显示出来但连不上。

QuanX 兼容的关键点（依据 QuanX 官方 `sample.conf` v1.5.5 build 914）：

- 只走 TCP + Reality + Vision，不用 WS / gRPC / XHTTP
- 必须写 `obfs=over-tls` + `obfs-host=<SNI>`，有 `reality-base64-pubkey` 时 QuanX 才会把标准 TLS 换成 Reality
- 必须写 `vless-flow=xtls-rprx-vision`，`method=none`
- **不要开 TCP Fast Open**：Reality 下 QuanX 用 iOS 26 Safari 指纹，Client Hello 超 1500 字节，Fast Open 注定失败；脚本输出的行里 deliberately 不带 `fast-open`
- 开 Reality 后自定义 ALPN / session ticket 会被忽略，不用再加
- `shortId` 16 位 hex，与官方示例 `0123456789abcdef` 同长
- 服务端 `realitySettings` 里没有 `fingerprint` 字段（那是客户端的），脚本不往里加；客户端指纹体现在链接的 `fp=chrome` 和 QuanX 的 Safari 指纹上

通用 `vless://` 链接（给其他客户端，如 sing-box / Shadowrocket / Loon）：

```text
vless://<UUID>@<服务器IP>:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=<你的邻居域名>&fp=chrome&pbk=<公钥>&sid=<shortId>&type=tcp&headerType=none#Reality-QuanX
```

## 可选参数

只在首次安装 / 无已有配置时生效，已有配置优先保留：

```bash
# 换端口 / 换伪装站 / 换节点名
REALITY_PORT=24443 REALITY_SNI=你的邻居域名 REALITY_TAG=Reality-US bash reality install

# 用域名做客户端地址（而不是自动探测的公网 IP）
REALITY_HOST=example.com bash reality install

# 指定 UUID / 指定 Xray 版本
REALITY_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx XRAY_VERSION=v26.10.31 bash reality install
```

## Cloudflare：端口、域名、防偷流量

这三条是硬规则，脚本安装前会直接校验，不合规就拒绝安装，不悄悄放行：

- **端口**：默认 443 保留。Reality 要冒充 443 上的真站，且客户端直连 VPS IP、不走 CF 反代，443 本身不是问题。**自定义端口绝不能是 CF 反代端口**：HTTP（80、8080、8880、2052、2082、2086、2095）和 HTTPS（2053、2083、2087、2096、8443）。例如 `REALITY_PORT=8443` 是错的，换 `24443` 这类不在列表里的端口。**端口要自定义或未占用**：默认 443 被 nginx 等服务占了，脚本自动改用 20000–60000 里随机挑的未占用、非 CF 端口，并在输出里明说换成了哪个；`REALITY_PORT` 显式指定的端口被占了，脚本直接报错停下，不悄悄换掉你指定的端口。
- **Reality 域名（dest / SNI）**：绝不能是 CF 的站，也不能是解析到 CF IP 的站。自动安装使用筛选结果，并由安装脚本检查域名及其解析地址。原理：鉴权失败的流量会原样回落转发到 dest，如果 dest 是 CF CDN 站，你的服务器就成了别人免费的 CF 端口转发，扫到后会被偷流量。根治办法是选非 CF 目标站，而不是开 `limitFallback*` 限速（那是可识别特征，XTLS 文档明确不建议一键脚本用）。
- **客户端地址**：`REALITY_HOST` 只能填 VPS 直连 IP，或未走 CF 反代的域名。填了 CF 反代域名，握手会被 CF 终结，QuanX 直接连不上。

## 仓库说明

- `reality`、`scan-neighbors.sh`、`auto-reality.sh`：三个脚本，见上表。
- `tests/`：不真装 Xray 的测试（替身 Xray + 替身扫描脚本），`bash tests/test-surge-output.sh`、`bash tests/test-xray-keys.sh`、`bash tests/test-menu.sh` 分别验 Surge/QuanX 输出、密钥解析、菜单/换端口/扫描重装/完全卸载。
- `vendor/`：扫描器（RealiTLScanner）和检测器（RealityChecker）的固定版本二进制 + 检测用的数据快照（CDN 关键词、热门站点、GFW 列表、国家数据库）。脚本下载它们时会校验 SHA-256，不匹配的不执行；检测数据不自动更新。
- 版本锁定：`auto-reality.sh` 拉取 `scan-neighbors.sh` 和 `reality` 时用的是固定提交，不是 main 的最新版——改了脚本要同步更新它里面的版本指向，修复才能生效。

## 常见问题

- **auto-reality.sh 报“检测到现有 Xray”**：机器上已经有节点，脚本怕覆盖直接停了。确认不要旧节点后先卸载再装：`bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) uninstall --purge`。`bash reality uninstall` 找不到文件，是因为 `reality` 脚本没落盘——一键命令是管道执行的，卸载也要用上面那行 curl 写法。
- **auto-reality.sh `--csv` 报“CSV 文件不存在”**：`--csv` 后面必须是已经扫出来的 `file.csv`，文件不存在就报错。先跑一遍扫描生成它，再 `--csv file.csv`。
- **扫描结果 0 行 / 没有符合条件的推荐域名**：这个网段上没扫到东西，或扫到了但没一个通过筛选（基础条件、状态 200、无 CDN、非热门、证书剩 14 天以上、解析匹配，缺一不可）。换个网段再扫（如相邻的 /24），或直接用已验证的域名手动装。
- **端口 443 被占**：默认 443 被占时脚本自动改用 20000–60000 里随机挑的未占用、非 CF 端口，并在输出里明说换成了哪个；`REALITY_PORT` 显式指定的端口被占了才直接报错。
- **QuanX 显示节点但连不上**：先确认 QuanX ≥ 1.5.5，再确认粘贴的是脚本输出的 QuanX 行（不是只导了链接），`obfs-host` / `reality-base64-pubkey` / `reality-hex-shortid` / `vless-flow` 四个参数一个都不能少。
- **Alpine 上服务起不来**：先看 `rc-service xray status`，再确认 `rc-update show` 里 `xray` 在 default 运行级；精简版 Alpine 的 OpenRC 由脚本自动安装。
- **Alpine 上 `apk add` 报 no such package / 依赖安装失败**：精简版 Alpine 出厂没有仓库索引，装任何包之前必须先 `apk update`；脚本装依赖和装二维码工具前都会自动跑一遍 `apk update`，手动装包也记得先 update。
- **Alpine 上没有二维码**：Alpine 里二维码命令行不在 `qrencode` 包里，在 `libqrencode-tools` 里，`apk add qrencode` 永远装不上；脚本已改成装 `libqrencode-tools`，装好后跑 `bash reality show` 可补生成。
- **Alpine 上扫描报错（`required file not found` / 提示装 python3）**：扫描器和检测器是 glibc 链接的，Alpine（musl）上要装 `gcompat` 才能跑；python3 缺了也要装。两个脚本都会自动装（Alpine 走 apk，Debian/Ubuntu 走 apt），手动装：`apk update && apk add python3 gcompat`。`apk add` 没有 `-y` 参数，别加。
- **私钥别外发**：私钥只在服务端 `/usr/local/etc/xray/config.json` 里，客户端只需要 UUID + 公钥 + shortId。
