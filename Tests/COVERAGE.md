# App registration and enforcement diagnostics

Build version 0.2.0 as rootless using the normal workflow. Users may convert that package with their RootHide patcher. Do not reuse the supplied 0.1.0 deb when testing these changes. The rootless YouTube crash is a separate deferred issue; stop that app's rootless test if it crashes and retain its log.

1. Install/respring. Fully terminate and relaunch the test app; an already running process retains the old code.
2. Keep Protection and Automatic prompts enabled. Delete any saved rule for the app to test a new request.
3. Open X/Twitter without other tweaks enabled for it. An injected, connected client should register shortly after hook setup, independently of network activity. Check Requests, Activity and Clients.
4. Choose Block In and Out. Request fresh remote content, preferably using the controlled LAN peer in DEVICE_TESTS.md. Cached content is not evidence of connectivity.
5. Check Clients for a recent timestamp and Socket traffic observed. Compare Activity with the fresh-content test. Choose Allow Both and retry to verify recovery. Repeat Block Incoming Only with the probe: sends may succeed, reads must fail.
6. Repeat with YouTube on the converted package, and Safari/Mail on each environment. Settings and SpringBoard intentionally do not register as filtered clients.

| Observation | Interpretation / next evidence |
| --- | --- |
| App absent from Clients | No valid check/registration reached the broker. Check per-app injection and collect client logs. |
| Client loaded log, no hook setup completed log | Initialization did not reach completion; inspect crash/startup logs. |
| Hook setup completed, broker reply missing | IPC or broker failure; covered operations should deny. |
| Recent registration, no socket traffic observed, fresh remote content succeeds | Traffic bypasses covered socket entries or originates in another process. A launch prompt does not close this gap. |
| Socket traffic observed and Blocked activity, but fresh remote content succeeds | Some flows are covered while others bypass them; capture the relevant networking process/path. |
| Old last-seen timestamp | Client may be suspended, terminated, disconnected, or replaced. A historical row is not current liveness. |
| Extra socket entries is zero | Optional exports were unavailable or aliases of public hooks; this is not proof that no public hooks were installed. |

Where available, use the device's unified log viewer with subsystem `com.netshield`, category `client`. For command-line collection, run `log stream --level info --predicate 'subsystem == "com.netshield"'` while relaunching the app. The device must provide the log utility; alternatively use a connected Mac's Console. Capture client loaded, hook setup completed, broker reply received/missing, and first IP socket intercepted. Logs deliberately omit destination addresses and request contents.

Record the app/version, jailbreak, injection settings, installed NetShield version, Clients row and Activity results. Client metadata is self-reported and cannot authenticate a hostile app.

System networking daemons, delegated WebKit/background transfers, direct syscalls and unhooked APIs remain outside complete enforcement. Do not claim all system processes are filtered. Supporting shared helpers requires request attribution and a separate enforcement design, not just enabling their injection or treating all helper traffic as Safari/Mail.
