# iOS 16 rootless / patched RootHide acceptance tests

Record device model, iOS version, jailbreak/injection version, package revision and RootHide patcher/version (when applicable) with results. None of these device tests has been run in the Windows authoring environment.

Run the suite separately on rootless and on a RootHide-converted package, without RocketBootstrap installed. On RootHide, use the converted probe path from the installed package rather than the rootless path below. Verify SpringBoard and app injection independently.

## Controlled traffic

1. On a LAN computer you control, run `python Tests/echo_peer.py tcp 8765`. Permit this listener through that computer's firewall only as needed for your test network.
2. Install the CI package, respring, unlock the phone, and open the NetShield dashboard once. Verify **Broker online**.
3. Through a terminal/SSH session on the phone run `/var/jb/usr/bin/netshield-probe tcp COMPUTER_IP 8765` as the mobile user. Use a numeric IP; do not use a hostname. Confirm the jailbreak injects into the probe. If there is no NetShield request and traffic succeeds, this is a failed injection/coverage test.
4. Before approval, expect `Permission denied` (`EACCES`) from connect/send and **no probe payload at the peer**. The app identity is `exec:` followed by its executable path. The probe retries every two seconds.
5. Choose **Block In and Out**. Expect denial on every retry and one saved Block Both rule, without recurring prompts.
6. Edit to **Block Incoming Only**. After cache refresh, expect the peer to receive payloads but the probe's `recv` to fail with EACCES. A TCP reply may still reach the kernel; this is expected for a userspace hook.
7. Edit to **Allow Both**. Expect the probe to send and receive echoed data.
8. Edit to **Block In and Out**. New outgoing attempts and hooked reads should be denied. Confirm no Allow In Only choice remains.
9. Delete the rule. Expect blocking and another prompt on subsequent attempts. Choose Later; verify the pending request remains and is editable in Requests without immediate re-prompting.
10. Repeat with `echo_peer.py udp 8765` and `netshield-probe udp COMPUTER_IP 8765`. UDP must be denied before the original `sendto`, not merely logged after sending.
11. Repeat TCP and UDP using IPv6: run the peer with `--ipv6` and use the computer's routable LAN IPv6 address. The simple probe does not parse link-local `%interface` scope suffixes.

Use packet capture on the controlled peer for independent evidence. A dashboard row alone does not demonstrate filtering. A missing dashboard row does not demonstrate absence of traffic.

## UI, lifecycle and regressions

| Case | Expected result |
| --- | --- |
| Two apps request simultaneously | One alert at a time; separate pending identities |
| Repeated attempts by one app | One queued prompt, bounded sampled history |
| Device locked before request | No prompt until unlock; hook still denies |
| Lock while alert/dashboard open | Overlay hides on polling interval; buttons cannot change rules while locked |
| Respring and relaunch probe | Rules persist; history/queue reset; first cache-warming call can fail |
| Disable automatic prompts | Unknown calls denied; request appears in dashboard |
| Disable protection | Calls permitted after async refresh; no new prompts |
| Re-enable protection | Existing block rules enforced on later checks |
| Existing connection revoked | Later hooked I/O denied after invalidation/expiry; in-flight/kernel traffic may finish |
| Broker unavailable | Intercepted calls denied after at most three seconds of stale allow; no caller thread waits for human/IPC |
| Broker stops responding, then recovers | Worker times out and later refreshes succeed without relaunching the app |
| Port 49671 already occupied before respring | Dashboard reports IPC unavailable; investigate the local port owner |
| Wi-Fi/cellular unavailable; airplane mode | Local policy requests still reach SpringBoard; external traffic may naturally fail |
| VPN/local-network permission changes | Verify loopback IPC works in each sandboxed test app; denied IPC must fail closed |
| Ordinary app loopback sockets | Remain subject to policy; no blanket loopback exemption |
| Remote connection to device port 49671 | No reply; broker binds only to 127.0.0.1 |
| File, pipe, AF_UNIX I/O | Normal local operations work; no access prompts |
| Reused/duplicated socket fd | Correct socket classification; no stale per-fd rule |
| No network | No alert loop; retry possible after reconnect |
| Settings/SpringBoard | Exempt from filtering for recovery and broker/UI |
| Safari/Mail and third-party apps | Register and prompt when injected; test their separate network paths rather than assuming complete coverage |
| Wi-Fi → cellular / VPN | Same rules apply; verify each app independently |
| Rule persistence write failure | Dashboard reports save failure; no claim that rule is durable |

Also test representative third-party apps using URLSession, WebKit, Network.framework and QUIC, plus background transfers and injection-disabled apps. **Document bypasses as failures of coverage, not successes because a different socket was blocked.** The probe only validates the particular BSD functions it calls. Exercise listen/accept and read/write/readv/writev/sendmsg/recvmsg with an app-level harness if those paths matter to your deployment.

If SpringBoard fails to present its overlay, collect its crash log, confirm the dashboard reports a working loopback listener, and inspect `SBLockScreenManager.isUILocked` and UIWindowScene behavior on that jailbreak. These are private interfaces requiring on-device validation.

## Launch registration and coverage

Follow [COVERAGE.md](COVERAGE.md) on rootless and separately after user-side RootHide conversion. Run X/Twitter and YouTube first, then Safari and Mail. A prompt without successful denial of fresh remote traffic is a coverage failure, not a pass. Verify old inbound-only rules become Block In and Out and old outbound-only rules retain their behavior under Block Incoming Only.
