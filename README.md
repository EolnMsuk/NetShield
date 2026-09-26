![NetShield](assets/banner.png)

# NetShield

**Per-app network access control for jailbroken iOS 16, by EolnMsuk.**

NetShield 1.0.0 is the first official release. Manage app access from a native dashboard, save allow/block rules, review activity, and optionally enable strict socket enforcement.

## Install

1. Download the rootless `.deb` from [Releases](https://github.com/EolnMsuk/NetShield/releases).
2. **RootHide users: convert the rootless deb with RootHide Patcher before installing.**
3. Install using your package manager with tweak injection and PreferenceLoader available, then respring.
4. Open **Settings > NetShield > Open NetShield Dashboard**.

Supports the current iOS 16 rootless target (arm64/arm64e). Other major iOS versions and stock iOS are not supported by this release.

## Use

**Protection and Automatic prompts are OFF on a fresh install.** Enable Protection in the dashboard's Settings when ready. Enable Automatic prompts for access alerts, or review Requests manually. Strict socket enforcement is optional and also starts OFF.

Choose **Allow Both**, **Block In and Out**, or **Block Incoming Only** for each app. Incoming includes replies to outgoing requests, so most apps need Allow Both. Retry or restart an app after changing its rule.

**Reset to Defaults** clears saved rules and history and turns all three switches OFF. Upgrades retain existing settings.

NetShield controls intercepted socket calls in injected apps. Shared networking helpers, unhooked paths and apps without injection can bypass rules; it is not a device-wide firewall. Strict enforcement can shut down covered sockets, requiring new connections after allowing access again.

[Technical details and project structure](projectstructure.md) | [GitHub](https://github.com/EolnMsuk/NetShield) | [Support EolnMsuk on Venmo](https://venmo.com/user/RustOnRails)

MIT licensed. Inspired by PyFirewall.
