# Troubleshooting

## `IPv4 forwarding is enabled. No changes made.`

The relay is not running in router mode. Check the process environment:

```sh
cat /proc/$(pidof python3)/environ | tr '\0' '\n' | grep PORTAL_BITRATE
ubus call service list '{"name":"portal-bitrate"}' | grep -A3 env
```

For the procd service, `env` must be passed in **one** list:

```sh
procd_set_param env PORTAL_BITRATE_ROUTER_MODE=1 PYTHONUNBUFFERED=1
```

Two separate `procd_set_param env ...` lines overwrite each other (only the last
one survives). For manual runs use `PORTAL_BITRATE_ROUTER_MODE=1 python3 ...`.
The `portal-bitrate` CLI exports the variable for you.

## `ERROR: ` with `_queue.Empty` in the log

The guardian child did not report `GUARD_READY` in time. On small routers a cold
Python + scapy start needs 40–60 s. The port already raises the timeout to 90 s;
if it still happens, run `python3 -m compileall -q /usr/lib/portal-bitrate/`
and check available RAM (`free -m`).

## Two relays at once, or `portal-bitrate session` does not stop the service

Do not mix a manual `run`/`session` with the procd service. On conflict, clean up:

```sh
/etc/init.d/portal-bitrate stop
for p in $(ps w | grep '[p]ortal_auto' | awk '{print $1}'); do kill -TERM $p; done
sleep 20
rm -f /var/run/portal-lab-capture.lock
nft delete table inet portal_bitrate_guard
/etc/init.d/portal-bitrate start
```

## Portal cannot reach the PS5 at all (mid-session freeze, then no connection)

The relay was killed without running its recovery handler, so the Portal's ARP
entry for the PS5 still points at the relay host.

```sh
portal-bitrate repair      # corrective ARP + guard table removal
```

ARP entries also expire by themselves (tens of seconds). A leftover guard table
only blocks the `Portal → PS5` direction and never affects `PS5 → Portal` video.

## `modified_packets_including_retransmits` stays 0

The captured startup packet does not match the recorded layout. Upstream
verified one Portal firmware layout (7.1.7); other firmware may differ. Nothing
is corrupted, but no bitrate change is applied. Options: try a different
`--profile`, or wait for upstream layout reports.

## `run` refuses to start: "Previous relay recovery is unconfirmed"

A previous crash left `recovery-required` in the runtime dir. Run:

```sh
portal-bitrate repair
```

## Baseline receipt is rejected after editing the code

The receipt (fingerprint) covers `portal_auto.py`, `portal_auto_platform.py`,
`portal_active_probe.py`, `portal_windows_network.py`, `protocol.py`. Any edit
invalidates it — re-run `portal-bitrate baseline` after modifying these files.

## Portal resolution drops to 720p/360p and stutters

Work through these in order — the relay is usually **not** the cause:

1. **CPU saturation on the router.** On OpenClash routers:
   - disable streaming auto-select: `uci set openclash.config.stream_auto_select=0 && uci commit openclash && /etc/init.d/openclash restart`
   - close any open LuCI **OpenClash** page in a browser (it spawns periodic
     network checks that push CPU to 80–100 %),
   - verify: `cat /proc/loadavg` should be well under 1.0 when idle, and
     `ps w | grep -c '[c]url'` should be small.
2. **Wi-Fi negotiation.** Check the Portal's negotiated rate on the AP:

   ```sh
   iwinfo rax0 assoclist
   ```

   A rate of ~78 Mbit/s (`20MHz`, `NSS 1`) means the Portal fell back to a
   narrow channel — disconnect/reconnect its Wi-Fi, or reboot the Portal.
3. **Weak PS5 signal.** The PS5 is the video sender; a PS5 RSSI of −65 dBm or
   worse plus a busy 2×2 radio (Portal + phone + …) caps the stream. Wire the
   PS5 to the router LAN if possible.
4. **Continuous relay overhead.** Prefer `portal-bitrate session` (bounded)
   over the permanent service on weak CPUs.

## Check that the scoped table is gone after stopping

```sh
nft list table inet portal_bitrate_guard   # expect: No such file or directory
ls /var/run/portal-lab-capture.lock        # expect: not found
```

If present after a hard kill, `portal-bitrate guard` removes the table and
`portal-bitrate repair` resets everything.
