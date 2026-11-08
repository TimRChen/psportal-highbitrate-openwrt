---
name: psportal-highbitrate-openwrt
description: Install, configure, verify and roll back the PS Portal high-bitrate relay on an OpenWrt/ImmortalWrt router (router-mode port of atameric/ps5-portal-high-bitrate). Use when a user wants to raise the PlayStation Portal → PS5 session bitrate target from the router itself, or when an installed relay does not patch a session and needs diagnosis.
license: MIT
---

# PS Portal high-bitrate relay — OpenWrt router skill

Operate this repository on a live router. Follow the steps in order; every step
has a pass condition. Never skip a gate and never improvise nftables.

## 0. Hard gates (stop if any fails)

| Gate | Check |
|---|---|
| OpenWrt / ImmortalWrt with `fw4` (nftables) | `nft --version` works, `/etc/config/firewall` uses fw4 |
| Root shell on the router | `id -u` = 0 |
| `python3` ≥ 3.9 and `scapy` ≥ 2.6 | `python3 -c 'import scapy'` |
| ≥ 35 MB free on `/overlay` | `df -k /overlay` |
| PS5 and Portal on the **same L2** as the LAN bridge | both resolve on `br-lan`, no client isolation |
| Both devices awake and enrolled | DHCP reservations or leases visible |
| Human accepts experimental risk | one Portal firmware layout only was validated upstream (7.1.7) |

Run the automated probe instead of doing this by hand:

```sh
sh skill/scripts/detect.sh
```

It prints JSON with `"ok": true|false` and a `reasons` array. If `ok` is false,
report the reasons and stop.

## 1. Install

```sh
sh skill/scripts/install.sh
```

Idempotent: installs `python3`/`python3-pip` if missing, `scapy==2.6.1` via pip,
copies the modules to `/usr/lib/portal-bitrate`, installs the procd service and
the `portal-bitrate` CLI, precompiles bytecode.

Pass condition: `portal-bitrate 2>&1 | head -1` prints the usage header.

## 2. Enroll (needs the two IPv4 addresses)

Discover them from the router (never guess):

```sh
cat /tmp/dhcp.leases
ip neigh show dev br-lan
```

Confirm which MAC is the PS5 and which is the Portal with the human before
enrolling — a swapped enrollment silently relays the wrong direction.

```sh
sh skill/scripts/configure.sh --ps5-ip <PS5_IP> --portal-ip <PORTAL_IP> --profile 65
```

The script validates the addresses, detects the LAN bridge (default `br-lan`),
enrolls both MACs by ARP and writes `/etc/portal-bitrate/auto-config.json`.
It refuses to continue if either device does not answer ARP.

## 3. Baseline (mandatory, no mutation)

The baseline relays the real `Portal → PS5` control traffic without changing any
byte and writes a receipt. It requires a **fresh session** inside the window, so
this is a human-in-the-loop step:

1. Start it in the background with a generous window:
   `portal-bitrate baseline --seconds 240 > /tmp/psportal-baseline.log 2>&1 &`
2. Poll the log until it contains `BASELINE READY` (allow ~90 s: the guardian is
   a cold Python + scapy process on small routers).
3. Tell the human: "disconnect the Portal from the PS5, then reconnect it now".
4. Wait for the run to end, then check
   `/var/lib/portal-bitrate/auto-baseline.json` exists with `"restored": true`
   and `forwarded_out > 0`.

Pass condition: receipt present, `forwarded_out > 0`, `errors: []`,
`recovery.json` clean (no `restoration_errors`).

## 4. Verify the mutation path (bounded, recommended first)

```sh
portal-bitrate arm 180      # background window; prints "ready" when armed
```

`arm` waits for `AUTO READY` itself and prints `ready: disconnect the Portal from
the PS5, then reconnect it now.` Tell the human that line verbatim, then poll
`/var/lib/portal-bitrate/status.json`:

Pass condition: `counts.modified_packets_including_retransmits >= 1` **and**
`counts.unique_modified_startups >= 1`, and the human confirms picture/controls.
If the counters stay 0, the packet layout does not match — do not retry blindly;
report the firmware version and stop. The window ends by itself and restores the
direct path; verify with `sh skill/scripts/verify.sh` afterwards.

## 5. Persist (only after step 4 passes)

```sh
/etc/init.d/portal-bitrate enable
/etc/init.d/portal-bitrate start
sh skill/scripts/verify.sh     # must show exactly one relay instance
```

Service mode patches every new session automatically but forwards all
`Portal → PS5` control packets through userspace. On weak CPUs prefer telling the
human to run `portal-bitrate session <secs>` before each play session instead.

## 6. Verification checklist

`sh skill/scripts/verify.sh` prints JSON. Require all of:

- `relay_instances` ∈ {0, 2} (main + guardian; never 4+)
- if the service is enabled: `service_running: true`
- `guard_table_present` matches the relay state (present only while running)
- `arp_restored: true` when no relay is running
- `baseline_receipt: true` before active runs
- `config_enrolled: true`

## 7. Diagnostics decision tree

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: IPv4 forwarding is enabled. No changes made.` | router-mode env missing (the procd `env` list was overwritten) | use the CLI, or one list: `procd_set_param env PORTAL_BITRATE_ROUTER_MODE=1 PYTHONUNBUFFERED=1` |
| `ERROR: ` + `_queue.Empty` | guardian didn't report in time (cold start) | verify timeout is 90 s, run `python3 -m compileall -q /usr/lib/portal-bitrate/`, check RAM |
| `modified_packets_including_retransmits` stays 0 | no fresh session captured / layout mismatch | ensure the relay was armed before the reconnect; report firmware |
| Portal shows a network-warning icon but streaming works | half-open IPv6 on the LAN (addresses advertised, no IPv6 uplink) — `detect.sh` reports `ipv6_half_open: true` | disable LAN IPv6 (see `docs/troubleshooting.md`), then toggle Wi-Fi on the Portal |
| Portal stutters, drops to 720p/360p | CPU saturation on the router (OpenClash streaming auto-select, LuCI OpenClash page polling), Wi-Fi 20 MHz fallback, weak PS5 RSSI | `uci set openclash.config.stream_auto_select=0 && uci commit openclash && /etc/init.d/openclash restart`; close LuCI OpenClash tabs; check `iwinfo rax0 assoclist`; wire the PS5 |
| Portal cannot reach the PS5 at all | stale spoofed ARP after an unclean kill | `portal-bitrate repair` |
| Two relays / port 7681 UI says one instance but two run | manual run + service | stop service, kill leftover `portal_auto.py`, remove lock, start service |
| guard table left behind | hard kill | `portal-bitrate guard` |
| `Previous relay recovery is unconfirmed` | crash left the marker | `portal-bitrate repair` |
| baseline receipt rejected | `module/*.py` edited after baseline | re-run baseline |

## 8. Rollback

```sh
sh skill/scripts/rollback.sh            # keeps /etc/portal-bitrate config
sh skill/scripts/rollback.sh --purge    # removes enrollment too
```

Then confirm: no `portal_auto.py` process, no `inet portal_bitrate_guard` table,
ARP entries for the PS5/Portal are back to the real MACs.

## 9. Hard rules

- Only the scoped table `inet portal_bitrate_guard`; never `nft flush`, never
  `inet fw4`, never `ip_forward`, never DNS/DHCP edits.
- One relay instance; never mix `session` with the service.
- Never claim 4K or guaranteed latency gains — this port does neither.
- Never publish the user's MACs/IPs/Wi-Fi keys/subscription URLs.
- Do not reboot the router unless the human asks.
