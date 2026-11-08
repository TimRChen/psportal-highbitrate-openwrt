# psportal-highbitrate-openwrt

**Run the PS Portal high-bitrate relay directly on an OpenWrt router.**

An OpenWrt **router-mode port** of [atameric/ps5-portal-high-bitrate](https://github.com/atameric/ps5-portal-high-bitrate)
(MIT). Upstream supports macOS, Windows, native Linux, Raspberry Pi, Proxmox LXC
and Docker macvlan — **router firmware is explicitly not a supported upstream
target**. This port adapts the automatic one-way relay so it can run on the LAN
gateway itself: no extra PC, no Raspberry Pi, no always-on second box.

> Status: **experimental**. Tested on one router (Cudy TR3000 v1 / ImmortalWrt
> 24.10 / MediaTek MT7981) and one PS Portal firmware layout that upstream
> verified (7.1.7). Not a jailbreak, not a 4K unlock, no guaranteed latency
> improvement. Use at your own risk on hardware you can recover.
>
> Maintained by [@TimRChen](https://github.com/TimRChen). Issues and firmware
> compatibility reports are welcome.

中文快速开始：[跳到中文](#中文快速开始)

---

## What it actually does

PlayStation Portal and PS5 negotiate a session startup packet ("LaunchSpec")
that contains a plaintext bitrate field (`25000`). The relay temporarily
redirects the **Portal → PS5 control direction** through itself, rewrites that
one field (`25000` → `65000` for profile `65`, or `1e+05` / `2e+05`), and lets
the session continue. The **PS5 → Portal video path is never relayed** — it
keeps the direct LAN path.

```
             ┌──────────── relay host (this port: the router itself) ───────────┐
Portal ──ARP──▶  control packets  ──▶  patch bitrate byte  ──▶  PS5
       (spoofed)                                                        │
Portal ◀──────────────── video (direct L2, never relayed) ◀─────────────┘
```

Profiles (from upstream): `65` (default recommendation), `100`, `200`
(experimental). Start with `65`.

## Why a router port needs changes

Upstream refuses to start when IPv4 forwarding is enabled, because a relaying
host must not forward the original frame itself — otherwise every relayed packet
arrives twice. A router **must** keep `net.ipv4.ip_forward=1`. This port solves
that with a scoped, self-removing `nftables` table instead of touching the global
firewall:

| Change | File |
|---|---|
| Router mode: skip the `ip_forward == 0` refusal (env `PORTAL_BITRATE_ROUTER_MODE=1`) | `module/portal_auto_platform.py` |
| Scoped `inet portal_bitrate_guard` table that drops only `Portal → PS5` forwarded duplicates | `module/portal_auto_platform.py` |
| Install guard on start, remove it on every stop/crash/guardian-exit path | `module/portal_auto.py` |
| Non-interactive `configure --interface --ps5-ip --portal-ip` | `module/portal_auto.py` |
| Configurable baseline window (`--seconds`) and guardian start timeout 10 s → 90 s | `module/portal_auto.py` |
| procd service + CLI wrapper + installer | `openwrt/`, `install.sh` |

Details: [`docs/openwrt-port-notes.md`](docs/openwrt-port-notes.md).

## Requirements

- OpenWrt / ImmortalWrt 23.05+ or 24.10+ with `nftables` (fw4), `ip-full`,
  `nft`, `root` access.
- ~35 MB free overlay space (Python 3 + scapy).
- Enrolled devices on the **same IPv4 L2 segment** as the router LAN bridge
  (`br-lan`), no client isolation, no VLAN between them.
- PS5 and Portal IPv4 addresses reserved in DHCP.

## Install

```sh
opkg update
opkg install python3 python3-pip
pip3 install --break-system-packages scapy==2.6.1

# from the extracted release / git checkout on the router
sh install.sh
```

Installs to `/usr/lib/portal-bitrate`, `/etc/init.d/portal-bitrate`,
`/usr/bin/portal-bitrate`; config in `/etc/portal-bitrate/auto-config.json`;
runtime state in `/var/lib/portal-bitrate`.

## First run

```sh
# 1) enroll: PS5 and Portal awake; interface is the LAN bridge
portal-bitrate configure --interface br-lan \
  --ps5-ip 192.168.1.100 --portal-ip 192.168.1.101 --profile 65

# 2) baseline: no mutation, proves the relay path works
#    Disconnect the Portal from the PS5 first, then reconnect within the window.
portal-bitrate baseline --seconds 240
#    -> wait for "BASELINE READY", reconnect the Portal, play ~30 s
#    -> a receipt is written only if control traffic was forwarded and recovery succeeded

# 3) active trial (65 Mbps target)
portal-bitrate session 300
#    -> wait for "AUTO READY", disconnect + reconnect the Portal, play
#    -> Ctrl+C / window end restores the direct path

# 4) persist: every new Portal session gets patched automatically
/etc/init.d/portal-bitrate enable
/etc/init.d/portal-bitrate start
```

Verify on the router:

```sh
portal-bitrate status
# counts.modified_packets_including_retransmits / counts.unique_modified_startups
# increase once per freshly negotiated session
```

Verify on the Portal: picture/controls must be checked by hand — the relay
cannot prove PS5 acceptance or measured video throughput.

## Operations

```sh
portal-bitrate status            # state + counters
portal-bitrate session [secs]    # bounded on-demand window (no permanent relay)
portal-bitrate repair            # after a crash: corrective ARP + remove guard table
portal-bitrate guard             # emergency: remove only the scoped nftables table
/etc/init.d/portal-bitrate start|stop|enable|disable
```

Uninstall:

```sh
sh uninstall.sh          # keeps /etc/portal-bitrate config, removes everything else
sh uninstall.sh --purge  # also removes the enrollment
```

## Important caveats

1. **Continuous relay vs on-demand.** Running the relay permanently (service
   mode) patches every new session automatically, but all Portal → PS5 control
   packets are then forwarded in userspace. On very weak CPUs use
   `portal-bitrate session` before playing instead — the patch is applied once
   and the direct path is restored.
2. **CPU spikes look like "the relay broke streaming".** On routers running
   OpenClash, disable *streaming auto-select* (`openclash.config.stream_auto_select=0`)
   and do not leave LuCI **OpenClash** pages open in a browser: they spawn
   periodic network checks that saturate the CPU and can force the Portal to
   drop resolution. See [`docs/troubleshooting.md`](docs/troubleshooting.md).
3. **Firmware sensitivity.** The mutation matches a recorded packet layout. If
   `modified_packets_including_retransmits` does not increase, the layout does
   not match; nothing is corrupted, but no bitrate change happens either.
4. **Recovery.** If the relay dies, the guardian restores the Portal's ARP entry;
   if that fails, run `portal-bitrate repair`. A stale guard table only blocks
   Portal → PS5 control traffic until removed.
5. **No 4K, no guaranteed 200 Mbps.** Target bitrate reported by the PS5 is not
   measured video throughput.
6. **Thermals.** A small travel router running 24/7 as gateway + AP + proxy +
   relay runs hot; improve airflow, or use on-demand session mode.

## License

MIT. Upstream copyright and license preserved — see [`LICENSE`](LICENSE) and
[`NOTICE.md`](NOTICE.md). Independent community software; not affiliated with
Sony, PlayStation, the upstream author or OpenWrt.

---

## 中文快速开始

**这是一个把 [atameric/ps5-portal-high-bitrate](https://github.com/atameric/ps5-portal-high-bitrate)
（MIT）移植到 OpenWrt 路由器上运行的项目**，目标是让路由器自己充当 relay，
不需要额外电脑/树莓派。

> 状态：实验性。仅在 Cudy TR3000 v1（ImmortalWrt 24.10 / MT7981）+ 上游验证过的
> Portal 固件布局上测试过。不是破解、不解锁 4K、不保证降低延迟。

### 安装

```sh
opkg update
opkg install python3 python3-pip
pip3 install --break-system-packages scapy==2.6.1
sh install.sh
```

### 首次配置

```sh
# 登记设备（PS5 / Portal 都要在线，接口为局域网网桥）
portal-bitrate configure --interface br-lan \
  --ps5-ip 192.168.1.100 --portal-ip 192.168.1.101 --profile 65

# 基线测试（不修改任何包）
# 先断开 Portal 与 PS5 的连接；看到 BASELINE READY 后再连回去玩 30 秒
portal-bitrate baseline --seconds 240

# 正式试验（65Mbps 目标码率）
portal-bitrate session 300
# 看到 AUTO READY 后：断开 Portal → 重新连接 PS5 → 玩；窗口结束自动恢复直连

# 常驻（每次新会话自动打补丁）
/etc/init.d/portal-bitrate enable
/etc/init.d/portal-bitrate start
```

### 查看与排障

```sh
portal-bitrate status     # 看 counts：modified_packets / unique_modified_startups 每次新会话 +1
portal-bitrate repair     # 异常后：纠正 ARP + 删除 guard 表
portal-bitrate guard      # 应急：只删 scoped nft 表
```

**常见坑**：

1. 路由器开着 OpenClash 时，先关闭「流媒体自动选路」
   （`uci set openclash.config.stream_auto_select=0`），并且**不要长期开着
   LuCI 的 OpenClash 页面**——它会在路由器上周期性跑网络检测，把 CPU 打满，
   导致 Portal 降分辨率（看起来像"relay 把串流搞卡了"）。
2. 如果 `modified_packets_including_retransmits` 不增长，说明你的 Portal 固件
   握手包布局不匹配，此时不会改包也没有副作用。
3. 崩溃后 Portal 可能短暂连不上 PS5：`portal-bitrate repair` 即可；ARP 条目
   本来也会在几十秒内自动过期。
