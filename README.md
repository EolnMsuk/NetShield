# NetShield

An experimental iOS 16 rootless jailbreak port of PyFirewall's **default-block, ask, then remember** concept. Written in Objective-C/Objective-C++ with Theos. The dark native dashboard has Requests, Activity, Rules, Clients, and Settings pages. Open it through **Settings → NetShield → Open NetShield Dashboard**.

**This is a userspace socket-hook prototype, not a device-wide firewall.** It has not yet been compiled with the iOS SDK or tested on a jailbroken device in this workspace. Build with the included workflow and complete the device tests below before relying on it. Stock iOS is unsupported.

## What is implemented

- Injected clients register on launch and every five seconds while running. Unknown clients can prompt before any socket traffic is observed. The Clients page distinguishes registration from observed socket checks.
- Intercepted unknown IPv4/IPv6 attempts immediately return `-1` / `EACCES` before calling the original network function.
- SpringBoard queues an access prompt: **Block Incoming Only**, **Block In and Out**, **Allow Both**, or **Later (Remain Blocked)**.
- No network thread waits for a human decision. The app must retry after approval; NetShield does not replay requests. A first attempt can fail even for an existing allow rule while the asynchronous policy cache warms up.
- Persistent per-bundle-ID rules, with executable-path identity for an explicitly injected command-line process. Extensions have their own identities.
- Requests are deduplicated by identity. Later defers automatic re-prompting until respring; the request remains in the dashboard. Delete a saved rule to ask again on the next attempt.
- Separate send/receive permissions. **Inbound means receiving bytes, including replies to an outgoing connection.** Most normal applications need Allow Both. This differs from a stateful firewall's inbound-connection rule.
- Rules apply to Wi-Fi, cellular, VPN and local IP traffic alike. Adapter-specific rules are not implemented: a device's current default interface is not a reliable indication of the interface used by each socket.
- At most 100 pending identities and 250 sampled activity checks in memory. History is **not** a live socket inventory, packet capture or byte counter. The client samples at most once per second per process, so short flows and some directions will not appear.
- Protection and automatic-prompt switches, rule editing/removal, clear activity, and a broker status indicator.
- Prompts wait while the device is locked. An existing overlay is hidden on the next 750 ms lock poll; this is not an instantaneous privacy guarantee. Actions check lock state again before modifying rules.

## Enforcement boundary

The filter matches UIKit/UIKitCore bundles or the UIApplication class, plus explicit SpringBoard and probe executable entries. Both third-party and Apple apps are now eligible for filtering. Settings remains exempt for recovery; SpringBoard runs the broker/UI without socket hooks. This is still an app-oriented injection filter, not blanket injection into system daemons. Apps/extensions that do not match it or have injection disabled are not covered.

Each injected client starts a five-second registration/refresh timer after hook setup. Unknown registered clients enter Requests even if their traffic uses an unhooked path. Clients shows the latest PID, last contact, completion of hook setup, extra entry-point count, and whether an IP socket check reached the broker. Registration and a displayed rule do not prove enforcement. See [Tests/COVERAGE.md](Tests/COVERAGE.md) for the diagnostic procedure.

Hooks: `socket` (strict mode), `connect`, `connectx`, `listen`, `accept`, `send`, `sendto`, `sendmsg`, `write`, `writev`, `recv`, `recvfrom`, `recvmsg`, `read`, and `readv`. Optional internal and non-cancelable variants of connect, accept, sendto/sendmsg, recvfrom/recvmsg, and read/write/readv/writev are resolved at runtime. Missing symbols are skipped; addresses aliasing an existing hook are deduplicated. Known non-IP descriptors (files, pipes, AF_UNIX) pass through; unexpected socket-classification failures deny the operation. IPv4/IPv6 loopback and LAN sockets are subject to the same rules as Internet sockets.

**Known bypasses and limits:**

- Apps with injection disabled, direct syscalls, unavailable private entry points, unhooked APIs (including `sendfile` and batched/message variants), and code that bypasses hooked library entry points are outside coverage.
- Network.framework/QUIC, WebKit networking helpers, DNS services, background NSURLSession transfers and other delegated system work may bypass the client or be attributed to a helper. The requester is not reliably recoverable in this architecture. Safari and Mail are no longer explicitly exempt, but their separate networking helpers remain outside the app filter. An in-app rule alone cannot promise to control those helpers.
- Blocking a receive function prevents the app from reading bytes through that hook. It does **not** stop packets, TCP ACKs, handshakes on existing listeners, or retransmissions in the kernel. Already queued data and active transfers are not recalled when a rule changes.
- A Darwin notification invalidates cached rules; there is also a one-second activity-driven refresh and a three-second successful-reply expiry. Brief old-policy windows and calls already past the check are possible. Missing/failed broker replies deny intercepted calls. Policy checks use a nonblocking loopback UDP socket with a 250 ms reply wait on the dedicated worker. Dropped replies deny access until a later successful refresh; a fresh socket on every check allows recovery after respring.
- The injected client reports its own identity over local UDP IPC (`127.0.0.1:49671`). It is not authenticated with an audit token; malicious clients can spoof checks and fill the bounded request queue. The Clients page contains self-reported diagnostics and is not an authenticated process inventory. There is no IPC rule-write endpoint. Requests carry a random correlation ID, but the broker is not cryptographically authenticated: a hostile local process that occupies the port before SpringBoard can impersonate it. Port conflicts make the real broker report an IPC failure. This transport is loopback-only; it does not expose a LAN listener. This is a convenience control for cooperative apps, not protection against hostile apps or other tweaks. A production security boundary requires authenticated IPC and OS-level enforcement.
- Windows-specific features such as Defender rules, domain/CIDR rules, CSV export, upload thresholds and tray integration are not ported.

For reliable device-wide pre-egress filtering and original-app attribution, a separate privileged filtering/provider design is required. This project does not assume that Network Extension entitlements or a kernel filtering facility are available just because the device is jailbroken.

## Strict socket enforcement (0.3.0, opt-in)

The default remains the tested socket-check behavior. In dashboard Settings, enable **Strict socket enforcement** to test stronger enforcement. The setting is saved and sent with policy replies; reset restores it to OFF.

- Once a client receives strict mode, intercepted IPv4/IPv6 `socket()` creation requires a fresh outgoing allow. Unknown/blocked clients get EACCES. AF_UNIX and NetShield's internal IPC worker remain unaffected.
- When a covered operation is denied under a fresh explicit rule, NetShield attempts kernel `shutdown()` on that IP socket: both directions for Block In and Out, receive for Block Incoming Only. This affects that socket even if later calls use unhooked functions. An inherited/earlier socket is affected only when it reaches a covered check; there is no background enumeration or blanket process revocation.
- The fd is duplicated only during shutdown to pin the socket. NetShield never closes the app-owned descriptor or keeps a descriptor cache. Shutdown can fail (for example for some unconnected sockets); the intercepted call still fails with EACCES.
- Unknown rules, expired replies, IPC failures and invalid policy data do not irreversibly shut down sockets. They still deny covered operations. Switching to Allow Both, disabling strict mode or resetting does not undo shutdown: the app must establish new sockets, sometimes requiring a relaunch. In-flight data is not recalled.

This is **not a catch-all kernel firewall**. A direct socket syscall can bypass the creation hook. Uninjected processes, delegated WebKit/background transfers, shared helpers, and untouched sockets can still bypass an app's rule. Socket creation can also precede the initial strict-mode reply. Never interpret a prompt or a Clients row as proof of complete traffic interception.

A true system-wide implementation requires a separate OS-level filter with reliable app attribution and supported deployment on the target jailbreak. Apple's Network Extension providers have entitlement and deployment requirements; a rootless package or RootHide conversion alone does not establish these capabilities. See [Apple's deployment guidance](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment). Do not blindly inject into all system daemons or block a shared helper as though it belongs to one app.

## Build on GitHub

The workflow is **`.github/workflows/build.yml`** inside this folder. GitHub discovers workflows only at the repository root:

1. **Recommended:** create a repository whose root contains the contents of `NetShield`, including the hidden `.github` folder.
2. If keeping NetShield inside the PyFirewall repository, copy `NetShield/.github/workflows/build.yml` to the repository's top-level `.github/workflows/build.yml`. The workflow automatically detects the nested project. A nested workflow alone will not run.
3. Open **Actions → Build NetShield → Run workflow**. Pushes/PRs touching the project also run it.
4. Download the **NetShield-iOS16-rootless** artifact and extract the `.deb`.

The job uses a macOS runner, Apple's clang for `arm64` + `arm64e`, Theos, the pinned iOS 16.5 SDK release, host policy, IPC and broker registration tests, and rootless packaging. The package includes the optional diagnostic probe (`BUILD_PROBE=1`). Theos itself tracks its upstream default branch; the exact revision, SDK checksum and Xcode version are included in diagnostics. No signing certificate or GitHub secret is needed for a jailbreak package. CI produces artifacts, not a published release.

The [Theos rootless documentation](https://theos.dev/docs/rootless) describes the install prefix, `iphoneos-arm64` packaging and arm64e toolchain requirements. The workflow uses the [official Theos SDK release](https://github.com/theos/sdks/releases/tag/master-146e41f). Policy messaging uses system UDP sockets bound to loopback, with no third-party IPC library or bootstrap Mach-service lookup. The client uses its existing app network permissions; sandbox or VPN policies that deny loopback cause checks to fail closed. RootHide conversion still requires device validation; a successful patch alone does not establish injection or IPC compatibility.

Local macOS/Theos build:

```sh
export THEOS="$HOME/theos"
cd NetShield
gmake clean package FINALPACKAGE=1 BUILD_PROBE=1
```

Install the 16.5 SDK in `$THEOS/sdks` first. Omit `BUILD_PROBE=1` to omit the command-line test tool. The workflow installs the required build dependencies. Project sources and resource files are included; SDKs and Theos are fetched during the build.

## Install and use

1. Use an iOS 16 rootless jailbreak with tweak injection and PreferenceLoader. No additional IPC library is required. Satisfy dependencies in your package manager; do not force-install through missing dependencies.
2. On rootless, install the `.deb` using Sileo/Zebra and respring. On RootHide, convert the rootless package using your patcher, install it, enable injection for SpringBoard and the test apps, then respring. The package targets `/var/jb` through Theos's rootless scheme, not a hand-prefixed layout.
3. Open Settings → NetShield. Check that the dashboard reports **Broker online**. Protection is enabled by default.
4. Force-close and relaunch a third-party app so the tweak is loaded. Trigger a request, choose a rule, then retry. Most apps should use **Allow Both**.
5. Review blocked requests and saved rules in the dashboard. Turning off automatic prompts still blocks unknown identities. Turning off protection permits intercepted traffic after policy refresh.

The rule choices are **Block Incoming Only** (allow sends, deny receives), **Block In and Out**, and **Allow Both**. Incoming includes replies to outgoing connections; this is not a stateful firewall. Existing Allow Out Only rules retain their behavior and get the new label. Retired Allow In Only rules become Block In and Out when loaded, without granting new access; choose a new rule explicitly if desired.

Rules/settings are atomically saved by SpringBoard to `/var/mobile/Library/Preferences/com.netshield.state.plist` (mode 0600). This is mobile user data, separate from the rootless package install tree. Save failures are shown in the dashboard. Pending requests and history disappear on respring. Uninstalling leaves this preferences file for reinstallation; remove that one file and respring if you want to reset all settings.

To start over, open the dashboard's **Settings > Reset to Defaults** and confirm. This clears saved rules and app names, pending requests, activity, and client records, restores Protection and Automatic prompts to ON and Strict socket enforcement to OFF, saves the default state, and invalidates client policy caches. Running apps will register again and may generate new prompts; client/activity lists need not remain empty. If saving fails, the dashboard reports that changes are in memory only.

Recovery: disable NetShield in your jailbreak's tweak manager and relaunch affected apps/respring, or uninstall the package in safe mode. The normal Settings process is exempt from filtering. No OS firewall configuration is changed by installation.

## Test before relying on it

See [Tests/DEVICE_TESTS.md](Tests/DEVICE_TESTS.md). The included `netshield-probe` and LAN echo peer let you distinguish a successful prompt from actual denial of socket calls. A successful build does not establish coverage of real apps or private SpringBoard behavior.

Source checks: `python3 Tests/validate.py`. Host policy checks:

```sh
clang -std=c11 -Wall -Wextra -Werror Tests/policy_test.c -o /tmp/netshield-policy-test
/tmp/netshield-policy-test
```

Local validation on Windows: plist/layout checks and C policy/cache-expiry assertions passed (MSVC, warnings treated as errors). This validates the portable decision logic, not the Objective-C++/Logos build or on-device enforcement.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/Tweak.xm` | Injection exclusions and BSD socket hooks |
| `Sources/Client.mm` | Nonblocking client and bounded-age policy cache |
| `Sources/AdditionalHooks.mm` | Optional internal/non-cancelable socket entry points |
| `Sources/IPC.mm` | Bounded loopback UDP policy transport |
| `Sources/Broker.mm` | SpringBoard request queue, policy store, history |
| `Sources/Dashboard.mm` | Dark dashboard and allow/block prompts |
| `Sources/SocketEnforcement.h` | Short-lived fd pinning and kernel shutdown for strict mode |
| `Sources/Policy.h` | Portable directional rule evaluator |
| `Preferences/` and `layout/` | Settings entry and resources |
| `Tests/` | Host tests, device probe and echo peer |
| `.github/workflows/build.yml` | Build, tests and `.deb` artifacts |

MIT license; based on the PyFirewall concept and UI organization. This is an independent experimental implementation, not a claim of feature parity with Windows Defender Firewall.
