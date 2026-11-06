# Xray VLESS + REALITY 一键脚本（主攻 Quantumult X）

服务端用 Xray-core，协议是 **VLESS / TCP + REALITY + xtls-rprx-vision**，默认 443 端口、伪装 `www.amazon.com:443`。输出以 Quantumult X（QuanX）优先：直接给能粘贴到 `[server_local]` 的 QuanX 行，再给通用 `vless://` 链接。

## 适用环境

- Debian 11/12/13
- Ubuntu 20.04 / 22.04 / 24.04
- Alpine Linux（OpenRC；精简版没预装 OpenRC 也能装，脚本会先装上再检测）
- root 或可 sudo 的用户
- QuanX **1.5.5+** 才支持 VLESS Reality + Vision，低版本请先升级 QuanX

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality)
```

无终端（管道）时直接安装；有终端时进菜单：安装 / 查看配置 / 更新 / 重启 / 卸载。

也可以直接指定操作：

```bash
# 查看客户端配置（QuanX 行 + vless://）
bash reality show

# 只换 Xray 二进制，UUID / 密钥 / 端口全部保留
bash reality update

# 卸载程序，保留配置，重装会继续用它
bash reality uninstall

# 彻底卸载，同时删配置和客户端文件
bash reality uninstall --purge
```

如果服务器没有 `curl`：

```bash
# Debian / Ubuntu
apt update && apt install -y curl

# Alpine
apk add --no-cache bash curl

bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/main/reality)
```

脚本会自动完成：

- 按架构下载 Xray-core（默认最新版，失败回落到已验证的 `v26.10.31`），有 `.dgst` 就验 sha256
- 用 `xray x25519` 生成 Reality 密钥对，用 `xray uuid` / 系统随机生成 UUID，shortId 固定 16 位 hex
- 写 `/usr/local/etc/xray/config.json`，`xray -test` 校验通过才启动
- 创建并启动 systemd 或 OpenRC 服务 `xray`，开机自启
- UFW / firewalld / iptables 放行端口（尽力而为）
- 输出客户端配置并保存到 `/root/xray-reality-client.txt`

重装 / 升级时，已有配置的 UUID、私钥、端口、SNI、shortId 全部保留，不会悄悄换掉客户端配置。

默认伪装站选 `www.amazon.com` 而不是更常见的 `www.apple.com` / `www.microsoft.com`，是因为实测 Xray 26.10.31 对后两者会警告“会增加服务器 IP 被 GFW 封的概率”，对 `www.amazon.com` 则不警告。想跟已有 sing-box 节点保持一致，可用 `REALITY_SNI=www.apple.com` 改回去，服务端与 QuanX 行的 SNI 会一起变。

## Quantumult X 配置（重点）

安装完成后，**优先用这一行**，粘贴到 QuanX 配置的 `[server_local]`：

```ini
vless=服务器IP:443, method=none, password=<UUID>, obfs=over-tls, obfs-host=www.amazon.com, reality-base64-pubkey=<公钥>, reality-hex-shortid=<16位hex>, vless-flow=xtls-rprx-vision, udp-relay=true, tag=Reality-QuanX
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
vless://<UUID>@<服务器IP>:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.amazon.com&fp=chrome&pbk=<公钥>&sid=<shortId>&type=tcp&headerType=none#Reality-QuanX
```

## 可选参数

只在首次安装 / 无已有配置时生效，已有配置优先保留：

```bash
# 换端口 / 换伪装站 / 换节点名
REALITY_PORT=24443 REALITY_SNI=www.apple.com REALITY_TAG=Reality-US bash reality install

# 用域名做客户端地址（而不是自动探测的公网 IP）
REALITY_HOST=example.com bash reality install

# 指定 UUID / 指定 Xray 版本
REALITY_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx XRAY_VERSION=v26.10.31 bash reality install
```

## Cloudflare：端口、域名、防偷流量

这三条是硬规则，脚本安装前会直接校验，不合规就拒绝安装，不悄悄放行：

- **端口**：默认 443 保留。Reality 要冒充 443 上的真站，且客户端直连 VPS IP、不走 CF 反代，443 本身不是问题。**自定义端口绝不能是 CF 反代端口**：HTTP（80、8080、8880、2052、2082、2086、2095）和 HTTPS（2053、2083、2087、2096、8443）。例如 `REALITY_PORT=8443` 是错的，换 `24443` 这类不在列表里的端口。**端口要自定义或未占用**：默认 443 被 nginx 等服务占了，脚本自动改用 20000–60000 里随机挑的未占用、非 CF 端口，并在输出里明说换成了哪个；`REALITY_PORT` 显式指定的端口被占了，脚本直接报错停下，不悄悄换掉你指定的端口。
- **Reality 域名（dest / SNI）**：绝不能是 CF 的站，也不能是解析到 CF IP 的站。默认 `www.amazon.com` 已实测不在 CF 后面。原理：鉴权失败的流量会原样回落转发到 dest，如果 dest 是 CF CDN 站，你的服务器就成了别人免费的 CF 端口转发，扫到后会被偷流量。根治办法是选非 CF 目标站，而不是开 `limitFallback*` 限速（那是可识别特征，XTLS 文档明确不建议一键脚本用）。
- **客户端地址**：`REALITY_HOST` 只能填 VPS 直连 IP，或未走 CF 反代的域名。填了 CF 反代域名，握手会被 CF 终结，QuanX 直接连不上。

## 常见问题

- **端口 443 被占**：脚本会提示，不悄悄换端口。先停掉占 443 的 nginx / 其他服务，或用 `REALITY_PORT` 换端口重装。
- **QuanX 显示节点但连不上**：先确认 QuanX ≥ 1.5.5，再确认粘贴的是脚本输出的 QuanX 行（不是只导了链接），`obfs-host` / `reality-base64-pubkey` / `reality-hex-shortid` / `vless-flow` 四个参数一个都不能少。
- **Alpine 上服务起不来**：先看 `rc-service xray status`，再确认 `rc-update show` 里 `xray` 在 default 运行级；精简版 Alpine 的 OpenRC 由脚本自动安装。
- **私钥别外发**：私钥只在服务端 `/usr/local/etc/xray/config.json` 里，客户端只需要 UUID + 公钥 + shortId。
