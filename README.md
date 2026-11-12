# Xray VLESS + REALITY 一键脚本

服务端 Xray-core，协议 **VLESS / TCP + REALITY + xtls-rprx-vision**，默认 443 端口。装完输出 Surge 行、Quantumult X（QuanX）行、通用 `vless://` 链接和二维码（终端打印一份，PNG 存 `/root/xray-reality-client.png`，手机扫码即导入）。

> ⚠️ 客户端配置保存在 `/root/xray-reality-client.txt`，内含连接凭据，请勿公开分享。

---

## 环境与依赖

- Debian 11/12/13、Ubuntu 20.04 / 22.04 / 24.04、Alpine Linux（OpenRC，精简版没预装 OpenRC 也能装）
- root 或可 sudo 的用户
- 依赖缺了脚本会自动装（Debian/Ubuntu 走 apt，Alpine 走 apk，会先 `apk update`）：

```bash
# Debian / Ubuntu
apt update && apt install -y curl python3

# Alpine
apk update && apk add --no-cache bash curl python3 gcompat
```

## 快速开始：先扫描，后安装

不要直接用默认域名装。先扫 VPS 所在网段，挑一个冷门邻居域名做 dest / SNI。

全自动，扫描 → 筛选 → 直接装好（推荐）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/auto-reality.sh)
```

手动两步，先扫、挑一个、再装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/scan-neighbors.sh)
REALITY_SNI=挑到的域名 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) install
```

扫不到合格域名时不硬停，改用 `www.apple.com` 直接装，并在输出里明说；机器上已有 Xray 时也会停下，以免覆盖现有节点。扫描只针对有权扫描的网段，VPS 上扫描可能被标记。

## 菜单与命令行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality)
```

有终端时进菜单，选完一项回到菜单，选 0 退出；无终端（管道）时直接安装。

| 菜单 | 作用 |
| --- | --- |
| 1. 查看客户端配置 | Surge 行 + QuanX 行 + vless:// 链接 + 二维码 |
| 2. 重新安装并扫描 Reality 域名 | 按本机 /23 → 相邻上段 /23 → 相邻下段 /23 的优先级扫邻居域名，哪个先扫到合格域名就用哪个重装，只换 dest / SNI，UUID、密钥、端口不变；都扫不到改用 `www.apple.com` 安装 |
| 3. 更换 Reality 端口 | 只换端口，域名、UUID、密钥、shortId 不变，同样过 CF 端口和占用检查 |
| 4. 完全卸载 | 删 Xray 程序、服务、配置、客户端文件和二维码，须输入 `yes` 才执行 |

也可以直接指定操作，不进菜单：

| 命令 | 作用 |
| --- | --- |
| `bash reality show` | 查看客户端配置（已有节点重新生成配置也用它） |
| `bash reality rescan` | 菜单 2：扫描邻居域名并重装 |
| `bash reality change-port` | 菜单 3：只换端口 |
| `bash reality reconfig` | 改伪装域名 / 端口 / 重新生成密钥，旧客户端配置全部作废 |
| `bash reality update` | 只换 Xray 二进制，配置全保留 |
| `bash reality restart` / `status` | 重启 / 查看服务状态 |
| `bash reality uninstall` | 卸载程序，保留配置 |
| `bash reality uninstall --purge` | 彻底卸载，配置、客户端文件、二维码一起删 |

安装时会问伪装域名：填筛选出的邻居域名，直接回车则回退到 `www.amazon.com`；填了 CF 站点或解析到 CF IP 的站点会被拒绝并重问（最多 3 次）。非交互安装不提问，用 `REALITY_SNI` 指定。

## 客户端配置

以下示例以洛杉矶节点为例，请用脚本输出的真实值。

**Surge** — 复制整行到配置的 `[Proxy]` 段。需 Surge iOS **6.0.0+** / Mac **6.12.0+**，REALITY 无需 `tls=true`，UDP relay 默认启用。详见 [Surge VLESS 官方文档](https://manual.nssurge.com/policies/vless.html)。

```ini
LA-Surge-Reality = vless, 服务器IP, 443, username=<UUID>, flow=xtls-rprx-vision, sni=<你的邻居域名>, reality-public-key=<公钥>, reality-short-id=<shortId>
```

**Quantumult X** — 复制整行到配置的 `[server_local]`，需 QuanX **1.5.5+**。不要只靠 `vless://` 链接导入，旧版解析器可能丢 `reality` 参数，节点显示出来却连不上。行里不带 `fast-open`：Reality 下 Client Hello 超 1500 字节，Fast Open 注定失败。

```ini
vless=服务器IP:443, method=none, password=<UUID>, obfs=over-tls, obfs-host=<你的邻居域名>, reality-base64-pubkey=<公钥>, reality-hex-shortid=<16位hex>, vless-flow=xtls-rprx-vision, udp-relay=true, tag=LA-Quanx-Reality
```

**通用 vless:// 链接**（sing-box、Shadowrocket、Loon 等）：

```text
vless://<UUID>@<服务器IP>:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=<你的邻居域名>&fp=chrome&pbk=<公钥>&sid=<shortId>&type=tcp&headerType=none#LA-Reality
```

### 节点名字

按服务器公网 IP 的所在地自动生成，地区简写全大写，Surge / Quanx / Reality 首字母大写：

| 客户端 | 名字（洛杉矶为例） |
| --- | --- |
| Surge | `LA-Surge-Reality` |
| QuanX `tag=` | `LA-Quanx-Reality` |
| vless:// `#` 后 | `LA-Reality` |

地区码如洛杉矶 `LA`、旧金山 `SF`、纽约 `NY`、法兰克福 `FRA`、香港 `HK`、新加坡 `SIN`、东京 `TYO`；不在映射表里的城市用城市名去空格转全大写，城市查不到用国家码，所在地查不到则不带地区码（`Surge-Reality` / `Quanx-Reality` / `Reality`）。`REALITY_TAG` 指定后三处都用指定的名字。名字只影响客户端显示，已导入的旧名字不会自动变，重新导入才会用新名字。

## 规则：端口与域名

硬规则，安装前校验，不合规直接拒绝，不悄悄放行：

- **端口**：默认 443。443 被占时自动改用 10000–30000 里随机挑的未占用、非 CF 端口，并在输出里明说；`REALITY_PORT` 显式指定的端口被占则直接报错。自定义端口绝不能是 CF 反代端口：
  - HTTP：`80` `8080` `8880` `2052` `2082` `2086` `2095`
  - HTTPS：`2053` `2083` `2087` `2096` `8443`
- **Reality 域名（dest / SNI）**：绝不能是 CF 站点或解析到 CF IP 的站点。鉴权失败的流量会原样回落到 dest，dest 若是 CF CDN 站，服务器就成了免费 CF 端口转发，会被偷流量。
- **客户端地址**：`REALITY_HOST` 只能填 VPS 直连 IP 或未走 CF 反代的域名，CF 反代域名会终结握手，直接连不上。

### 环境变量

只在首次安装 / 无已有配置时生效，已有配置优先保留：

| 变量 | 作用 |
| --- | --- |
| `REALITY_PORT` | 端口，默认 443，如 `REALITY_PORT=24443`（别用 CF 反代端口） |
| `REALITY_SNI` | 伪装域名（dest 与 serverNames 同值），默认 `www.amazon.com` |
| `REALITY_SCAN_CIDRS` | 扫描范围优先级，逗号或空格分隔，如 `154.9.238.0/23,154.9.234.0/23`；不指定则按本机 /23 → 相邻上段 → 相邻下段的顺序扫 |
| `REALITY_TAG` | 节点名，指定后三处都用它，不指定则按 IP 所在地自动生成 |
| `REALITY_HOST` | 客户端填的地址，默认自动探测公网 IP，也可填域名 |
| `REALITY_UUID` / `XRAY_VERSION` | 指定 UUID / Xray 版本，不指定则随机生成 / 取 GitHub 最新版 |

```bash
REALITY_PORT=24443 REALITY_SNI=你的邻居域名 REALITY_TAG=My-Node bash reality install
REALITY_HOST=example.com bash reality install
```

## 三个脚本

| 脚本 | 干什么 | 什么时候用 |
| --- | --- | --- |
| `auto-reality.sh` | 扫描邻居网段 → 筛选推荐域名 → 直接装好节点 | 新机器，想一步到位 |
| `scan-neighbors.sh` | 只扫描和筛选，输出 `file.csv` + 最多 3 个推荐域名 | 只想挑域名，或先看一眼再决定 |
| `reality` | 安装 / 查看 / 扫描重装 / 换端口 / 更新 / 卸载 | 直接装，或管理已有节点 |

扫描器自动探测公网 IP，扫所在 `/23`（512 个地址，443 端口），核对证书域名解析，再用 RealityChecker 检测，按握手延迟推荐最多 3 个域名（状态 200、非 CDN、非热门、证书剩余 ≥ 14 天、解析匹配，缺一不可）。`--csv file.csv` 可跳过扫描、用已有结果；`bash scan-neighbors.sh 154.9.236.158` 可指定 IP 或网段。

> ⚠️ `auto-reality.sh` 拉取 `scan-neighbors.sh` 和 `reality` 时用的是**固定提交**，不是 main 最新版。改了脚本要同步更新它里面的版本指向，修复才能生效。

## 常见问题

- **报“检测到现有 Xray”**：机器上已有节点，怕覆盖直接停了。确认不要旧节点后先卸载再装：`bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality) uninstall --purge`（一键命令是管道执行，`reality` 没落盘，卸载也要用 curl 写法）。
- **`--csv` 报“CSV 文件不存在”**：`--csv` 后面必须是已扫出来的 `file.csv`，先跑一遍扫描生成它。
- **扫描 0 行 / 没有推荐域名**：这个网段没扫到东西，或扫到的没通过筛选。全自动安装和扫描重装会直接用 `www.apple.com` 装；想用邻居域名就换个网段再扫（如相邻 /24），或用已验证的域名手动装（`REALITY_SNI=域名`）。
- **QuanX 显示节点但连不上**：确认 QuanX ≥ 1.5.5，确认粘贴的是脚本输出的 QuanX 行（不是只导了链接），`obfs-host` / `reality-base64-pubkey` / `reality-hex-shortid` / `vless-flow` 一个都不能少。
- **Alpine 上服务起不来**：看 `rc-service xray status`，确认 `rc-update show` 里 `xray` 在 default 运行级。
- **Alpine 上没有二维码**：二维码命令行在 `libqrencode-tools` 包里，不在 `qrencode` 里；脚本已改成装 `libqrencode-tools`，装好后跑 `bash reality show` 可补生成。
- **Alpine 上扫描报错**：扫描器和检测器是 glibc 链接的，Alpine（musl）上要装 `gcompat` 才能跑，脚本会自动装；手动装：`apk update && apk add python3 gcompat`（`apk add` 没有 `-y` 参数）。
- **私钥别外发**：私钥只在服务端 `/usr/local/etc/xray/config.json` 里，客户端只需要 UUID + 公钥 + shortId。

## 仓库说明

- `tests/`：不真装 Xray 的测试（替身 Xray + 替身扫描脚本），分别验 Surge/QuanX 输出、密钥解析、菜单 / 换端口 / 扫描重装 / 完全卸载。
- `vendor/`：扫描器（RealiTLScanner）和检测器（RealityChecker）的固定版本二进制 + 检测数据快照（CDN 关键词、热门站点、GFW 列表、国家数据库），下载时校验 SHA-256，不匹配的不执行，检测数据不自动更新。
