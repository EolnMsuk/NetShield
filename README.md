# NetShield

An experimental iOS 16 rootless jailbreak port of PyFirewall's **default-block, ask, then remember** concept. Written in Objective-C/Objective-C++ with Theos. The dark native dashboard has Requests, Activity, Rules, and Settings pages. Open it through **Settings → NetShield → Open NetShield Dashboard**.

**This is a userspace socket-hook prototype, not a device-wide firewall.** It has not yet been compiled with the iOS SDK or tested on a jailbroken device in this workspace. Build with the included workflow and complete the device tests below before relying on it. Stock iOS is unsupported.

## What is implemented

- Intercepted unknown IPv4/IPv6 attempts immediately return `-1` / `EACCES` before calling the original network function.
- SpringBoard queues an access prompt: **Keep Blocking**, **Allow In Only**, **Allow Out Only**, **Allow Both**, or **Later (Remain Blocked)**.
- No network thread waits for a human decision. The app must retry after approval; NetShield does not replay requests. A first attempt can fail even for an existing allow rule while the asynchronous policy cache warms up.
- Persistent per-bundle-ID rules, with executable-path identity for an explicitly injected command-line process. Extensions have their own identities.
- Requests are deduplicated by identity. Later defers automatic re-prompting until respring; the request remains in the dashboard. Delete a saved rule to ask again on the next attempt.
- Separate send/receive permissions. **Inbound means receiving bytes, including replies to an outgoing connection.** Most normal applications need Allow Both. This differs from a stateful firewall's inbound-connection rule.
- Rules apply to Wi-Fi, cellular, VPN and local IP traffic alike. Adapter-specific rules are not implemented: a device's current default interface is not a reliable indication of the interface used by each socket.
- At most 100 pending identities and 250 sampled activity checks in memory. History is **not** a live socket inventory, packet capture or byte counter. The client samples at most once per second per process, so short flows and some directions will not appear.
- Protection and automatic-prompt switches, rule editing/removal, clear activity, and a broker status indicator.
- Prompts wait while the device is locked. An existing overlay is hidden on the next 750 ms lock poll; this is not an instantaneous privacy guarantee. Actions check lock state again before modifying rules.

## Enforcement boundary

The filter injects into UIKit-linked processes and SpringBoard. The constructor exempts `com.apple.*` processes (including Settings); SpringBoard runs only the broker/UI. A non-UIKit daemon needs an explicit executable entry in `NetShield.plist` and device testing. Do not inject this broadly into system daemons. The diagnostic `netshield-probe` executable is already listed.

Hooks: `connect`, `connectx`, `listen`, `accept`, `send`, `sendto`, `sendmsg`, `write`, `writev`, `recv`, `recvfrom`, `recvmsg`, `read`, and `readv`. Non-IP descriptors (files, pipes, AF_UNIX) pass through. IPv4/IPv6 loopback and LAN sockets are subject to the same rules as Internet sockets.

**Known bypasses and limits:**

- Apps with injection disabled, direct syscalls, unhooked APIs (including `sendfile` and batched/message variants), and code that bypasses hooked library entry points are outside coverage.
- Network.framework/QUIC, WebKit networking helpers, DNS services, background NSURLSession transfers and other delegated system work may bypass the client or be attributed to a helper. The requester is not reliably recoverable in this architecture. Safari and other Apple apps are explicitly exempt.
- Blocking a receive function prevents the app from reading bytes through that hook. It does **not** stop packets, TCP ACKs, handshakes on existing listeners, or retransmissions in the kernel. Already queued data and active transfers are not recalled when a rule changes.
- A Darwin notification invalidates cached rules; there is also a one-second activity-driven refresh and a three-second successful-reply expiry. Brief old-policy windows and calls already past the check are possible. Missing/failed broker replies deny intercepted calls. If an IPC call hangs, its dedicated worker may remain stuck; hooks stay nonblocking and cached allows expire, but that process must be restarted to recover the worker.
- The injected client reports its own identity over public IPC. It is not authenticated with an audit token; malicious clients can spoof checks and fill the bounded request queue. There is no IPC rule-write endpoint. This is a convenience control for cooperative apps, not protection against hostile apps or other tweaks. A production security boundary requires authenticated IPC and OS-level enforcement.
- Windows-specific features such as Defender rules, domain/CIDR rules, CSV export, upload thresholds and tray integration are not ported.

For reliable device-wide pre-egress filtering and original-app attribution, a separate privileged filtering/provider design is required. This project does not assume that Network Extension entitlements or a kernel filtering facility are available just because the device is jailbroken.

## Build on GitHub

The workflow is **`.github/workflows/build.yml`** inside this folder. GitHub discovers workflows only at the repository root:

1. **Recommended:** create a repository whose root contains the contents of `NetShield`, including the hidden `.github` folder.
2. If keeping NetShield inside the PyFirewall repository, copy `NetShield/.github/workflows/build.yml` to the repository's top-level `.github/workflows/build.yml`. The workflow automatically detects the nested project. A nested workflow alone will not run.
3. Open **Actions → Build NetShield → Run workflow**. Pushes/PRs touching the project also run it.
4. Download the **NetShield-iOS16-rootless** artifact and extract the `.deb`.

The job uses a macOS runner, Apple's clang for `arm64` + `arm64e`, Theos, the pinned iOS 16.5 SDK release, host policy tests, and rootless packaging. The package includes the optional diagnostic probe (`BUILD_PROBE=1`). Theos itself tracks its upstream default branch; the exact revision, SDK checksum and Xcode version are included in diagnostics. No signing certificate or GitHub secret is needed for a jailbreak package. CI produces artifacts, not a published release.

The [Theos rootless documentation](https://theos.dev/docs/rootless) describes the install prefix, `iphoneos-arm64` packaging and arm64e toolchain requirements. The workflow uses the [official Theos SDK release](https://github.com/theos/sdks/releases/tag/master-146e41f). Cross-sandbox messaging uses the [RocketBootstrap API](https://github.com/rpetrich/RocketBootstrap/blob/master/rocketbootstrap.h).

Local macOS/Theos build:

```sh
export THEOS="$HOME/theos"
cd NetShield
gmake clean package FINALPACKAGE=1 BUILD_PROBE=1
```

Install the 16.5 SDK in `$THEOS/sdks` first. Omit `BUILD_PROBE=1` to omit the command-line test tool. The workflow installs the required build dependencies. Project sources and resource files are included; SDKs and Theos are fetched during the build.

## Install and use

1. Use an iOS 16 rootless jailbreak with tweak injection, PreferenceLoader, and a **rootless build of RocketBootstrap** providing `com.rpetrich.rocketbootstrap`. Satisfy dependencies in your package manager; do not force-install through missing dependencies.
2. Install the `.deb` using Sileo/Zebra and respring. The package targets `/var/jb` through Theos's rootless scheme, not a hand-prefixed layout.
3. Open Settings → NetShield. Check that the dashboard reports **Broker online**. Protection is enabled by default.
4. Force-close and relaunch a third-party app so the tweak is loaded. Trigger a request, choose a rule, then retry. Most apps should use **Allow Both**.
5. Review blocked requests and saved rules in the dashboard. Turning off automatic prompts still blocks unknown identities. Turning off protection permits intercepted traffic after policy refresh.

Rules/settings are atomically saved by SpringBoard to `/var/mobile/Library/Preferences/com.netshield.state.plist` (mode 0600). This is mobile user data, separate from the rootless package install tree. Save failures are shown in the dashboard. Pending requests and history disappear on respring. Uninstalling leaves this preferences file for reinstallation; remove that one file and respring if you want to reset all settings.

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
| `Sources/IPC.mm` | Dynamic AppSupport/RocketBootstrap setup |
| `Sources/Broker.mm` | SpringBoard request queue, policy store, history |
| `Sources/Dashboard.mm` | Dark dashboard and allow/block prompts |
| `Sources/Policy.h` | Portable directional rule evaluator |
| `Preferences/` and `layout/` | Settings entry and resources |
| `Tests/` | Host tests, device probe and echo peer |
| `.github/workflows/build.yml` | Build, tests and `.deb` artifacts |

MIT license; based on the PyFirewall concept and UI organization. This is an independent experimental implementation, not a claim of feature parity with Windows Defender Firewall.
