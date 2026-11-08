# OpenWrt router-mode port — technical notes

Upstream `ps5-portal-high-bitrate` is designed to run on a **host** that sits on
the same L2 segment as the PS5 and the Portal. Upstream explicitly lists router
firmware as unsupported (`AUTOMATION.md`), mostly because of one hard check:

> Both `/proc/sys/net/ipv4/ip_forward` and
> `/proc/sys/net/ipv4/conf/<iface>/forwarding` must be `0`.

A LAN gateway cannot satisfy that: it must forward. Enabling forwarding would
also make the kernel forward the ARP-redirected `Portal → PS5` frames itself, so
every relayed packet would be delivered twice (the kernel copy plus the relay's
re-injected copy).

## 1. Router mode

`module/portal_auto_platform.py`:

```python
ROUTER_MODE = os.environ.get('PORTAL_BITRATE_ROUTER_MODE') == '1'
...
elif sys.platform == 'linux':
    if not ROUTER_MODE:
        for path in ('/proc/sys/net/ipv4/ip_forward',
                     f'/proc/sys/net/ipv4/conf/{IFACE}/forwarding'):
            if Path(path).read_text().strip() != '0':
                raise RuntimeError('IPv4 forwarding is enabled. No changes made.')
```

The rest of `health()` (direct-route validation for both peers) is unchanged and
still runs in router mode.

## 2. Scoped nftables guard

Only the `Portal → PS5` direction is redirected by the relay (the video path
`PS5 → Portal` stays direct), therefore only that direction needs its
kernel-forwarded duplicate dropped:

```python
def nft_guard_add(portal_ip, ps5_ip):
    script = (
        'table inet %s {\n'
        '  chain guard {\n'
        '    type filter hook forward priority -5; policy accept;\n'
        '    ip saddr %s ip daddr %s drop\n'
        '  }\n'
        '}\n' % (NFT_TABLE, portal_ip, ps5_ip)
    )
    subprocess.run([NFT_BIN, '-f', '-'], input=script, text=True, check=True)
```

Design constraints kept from upstream's safety rules:

- a dedicated table name (`inet portal_bitrate_guard`) — never `nft flush`,
  never edits `inet fw4`;
- priority `-5` (runs before fw4's filter chains);
- only the exact `(portal_ip → ps5_ip)` pair is dropped;
- idempotent: an existing table is removed before re-adding;
- removed on **every** exit path (normal stop, guardian exit, `repair`, CLI
  `guard` emergency command).

## 3. Lifecycle hooks

`module/portal_auto.py`:

- `run()` installs the guard right after `state_for()` when `ROUTER_MODE` is set;
- `run()` removes it in its `finally` block;
- `guardian()` removes it after restoring the Portal ARP entry (crash path);
- `repair` removes it together with the stale lock file.

## 4. Small-router latency

The guardian is a separate Python process. On a MediaTek MT7981 (2× Cortex-A53
@1.3 GHz) a cold `import scapy` + boot takes 40–60 s, which is longer than the
upstream 10 s `GUARD_READY` timeout. The port raises it to 90 s and precompiles
bytecode in `install.sh`.

Write the readme-worthy consequence: prefer `portal-bitrate session` on weak
CPUs. A permanent relay forwards every `Portal → PS5` control packet through
userspace; that is cheap (≈3 % CPU on MT7981) but it is still an extra hop that
only exists while the relay runs.

## 5. procd service

`openwrt/portal-bitrate.init` is a `USE_PROCD=1` init script. Two details matter:

- **`env` is a list parameter** — call it once:
  `procd_set_param env PORTAL_BITRATE_ROUTER_MODE=1 PYTHONUNBUFFERED=1`.
  Two separate calls overwrite each other and the relay then fails with
  `IPv4 forwarding is enabled. No changes made.`
- `term_timeout 60` gives the relay enough time to run its recovery handler on
  `SIGTERM` before procd escalates to `SIGKILL`.

## 6. Non-interactive enrollment

`configure` accepts `--interface`, `--ps5-ip`, `--portal-ip` so the enrollment can
be scripted from a router shell (no TTY prompts). `--seconds` now also applies to
`baseline`, which is useful when the person has to walk to the console between
`BASELINE READY` and reconnecting the Portal.

## What was intentionally NOT changed

- The packet heuristic (`OFFSET=334`, `PATCH_DELTA` profiles, protobuf shape
  checks) is upstream code, unmodified.
- The one-way relay architecture (video never relayed) is upstream code,
  unmodified.
- Upstream's MIT license and copyright are preserved.
