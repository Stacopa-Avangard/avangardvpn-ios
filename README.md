# AvangardVPN — iOS

Native iOS client for **AvangardVPN**, mirroring the Android app
(`Stacopa-Avangard/avangardvpn-android`). Talks to the **same backend** (`Stacopa-Avangard/avangardvpn-server`,
`https://app.avangardvpn.com`) — no backend changes needed. That backend answers to a
second name, `vpn.stacopa-avangard.com`, which is a permanent alias onto the identical
origin and cannot be retired — Android compiled it into every shipped build.

## Architecture

Three targets in one Xcode project (defined by [`project.yml`](project.yml), XcodeGen):

| Target | What |
|---|---|
| **AvangardVPN** (app) | SwiftUI UI, poll-login, on-device keygen, region picker; tokens + private key in **Keychain**; API via `URLSession` |
| **AvangardTunnel** (app-extension) | `NEPacketTunnelProvider` — the WireGuard tunnel, driven by **WireGuardKit** (from `wireguard-apple`) |
| **AvangardVPNTests** (unit-test) | Integration tests against a locally-run backend — see [Tests](#tests) |
| App Group `group.com.avangard.vpn` | shares config between app ↔ extension |

- Bundle IDs: app `com.avangard.vpn`, tunnel `com.avangard.vpn.network-extension`
- Min iOS **16.0**; Swift 5.9 / SwiftUI
- The server holds **no private key** — the key is generated on device (CryptoKit) and stays in the Keychain, same as Android.

## Prerequisites (for signed/device builds)

- **Apple Developer Program** ($99/yr) — required for the NetworkExtension entitlement + TestFlight.
  ✅ **Paid 2026-09-02.** Apple only sends the payment link once Organization
  verification passes, so this also confirms `PT Stacopa Avangard Raya` cleared
  verification. `DEVELOPMENT_TEAM` is set in [`project.yml`](project.yml); a
  Team ID is not a secret, and leaving it blank meant `xcodegen generate` wiped
  the team from the project on every run.
- App IDs + capabilities: **Network Extensions** (packet-tunnel-provider) + **App Groups**
  on **both** bundle IDs — `com.avangard.vpn` and `com.avangard.vpn.network-extension` —
  plus the App Group `group.com.avangard.vpn`, which has to exist *before* either App ID can
  reference it. The extension needs both capabilities too: `NETunnelProviderManager` is gated
  on `packet-tunnel-provider` at the calling side as well as the providing side.

  On iOS this is self-serve — enabling the capability is enough, with no entitlement request
  to Apple. (The `networkextension@apple.com` request route is for macOS system extensions
  and content filters.)
- Signing via `fastlane match` (for CI) or Xcode automatic signing (local).

Three upload requirements are already met and needed **none** of the above —
app icon (see [Icon](#icon)), privacy manifest, and the export-compliance
declaration (both under
[Privacy manifest and export compliance](#privacy-manifest-and-export-compliance)).
The only export step left before a release is App Store Connect's own
questionnaire; the BIS filing that section describes looks backwards and is not
owed until the February after the app has actually shipped.

Everything through P2 (and the UI work in P4) needs none of this — it builds and
tests on the Simulator unsigned.

## Build

The project is **text-defined** (XcodeGen), so it can be authored on any OS and
compiled on macOS.

⛔ **Go 1.21 first, and only 1.21.** The wireguard-go bridge patches the Go
runtime so its monotonic clock follows boot time — that is what keeps WireGuard's
handshake and keepalive timers alive while the phone sleeps. The patch was
written against Go 1.17-1.21 and does not apply to an arbitrary newer runtime,
and the failure it prevents is a tunnel that dies silently overnight. CI pins
`go-version: "1.21"` for exactly this.

Homebrew is not the route: `go@1.21` is a **disabled** formula, so the install is
refused. Use the official archive — go.dev keeps every release ever shipped:

```bash
curl -LO https://go.dev/dl/go1.21.13.darwin-arm64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.13.darwin-arm64.tar.gz
/usr/local/go/bin/go version    # expect go1.21.13
```

⚠️ The bridge target spawns `/usr/bin/env make`, so it resolves `go` — and
`rsync` — from **Xcode's** build PATH, not your shell's. Measured on macOS 26 on
2026-09-02 by running `xcodebuild` under a sanitised environment: Xcode adds
nothing of its own, and `launchctl getenv PATH` is empty on a stock machine, so a
GUI-launched Xcode builds with exactly `/usr/bin:/bin:/usr/sbin:/sbin`. That
contains neither `/usr/local/go/bin` nor Homebrew's `/opt/homebrew/bin`, so
extracting Go and running `brew install rsync` is **not** enough on its own —
[Step 1](#step-1--go-121-and-only-121) carries the rest.

⛔ And the failure does not say `go: command not found`, which an earlier version
of this file promised. `Sources/WireGuardKitGo/Makefile:27` reads
`REAL_GOROOT := $(shell go env GOROOT 2>/dev/null)`, so the real error is
swallowed and the build reports only this:

```
/usr/bin/env make
[ -n "" ]
make: *** [.../wireguard-go-bridge/goroot/.prepared] Error 1
```

```bash
# On macOS (or CI):
brew install xcodegen
xcodegen generate            # writes AvangardVPN.xcodeproj (gitignored)
open AvangardVPN.xcodeproj    # develop / run on a device from Xcode
```

**CI** ([`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml)) does an
**unsigned iOS-Simulator build** on a macOS runner — a compile-check that needs **no
Apple account**. (VPN can't actually run in the Simulator — device testing needs a
real iPhone + signing.)

## ▶ Running it on a real iPhone (paid account) — start here

✅ **Done — 2026-09-03.** The tunnel came up on an iPhone 12 (iOS 26.6), region
Singapore, and carried real traffic: iOS system daemons (`cloudd`, `apsd`,
`featureaccessd`) routed over `utun5` with completed HTTPS transactions
(`err=F`), and the phone's public IP was Singapore. This section is kept because
the steps are still the steps — and because three things went wrong on the way
that the instructions did not predict. Those are in
[What the first Mac session found](#what-the-first-mac-session-found--2026-09-03).

Self-contained on purpose: follow it top to bottom on the Mac without reading the
rest of this file.

### Where things stand — 2026-09-03

| | |
|---|---|
| Apple Developer Program | ✅ paid. Apple sends the payment link only after Organization verification passes, so `PT Stacopa Avangard Raya` cleared it |
| `DEVELOPMENT_TEAM` | ✅ `8HSUX5T86H`, set in `project.yml` so `xcodegen generate` cannot wipe it |
| App ID `com.avangard.vpn` | ✅ Network Extensions + App Groups |
| App ID `com.avangard.vpn.network-extension` | ✅ same — the extension needs both too |
| App Group `group.com.avangard.vpn` | ✅ bound to both App IDs |
| App icon, privacy manifests, export declaration | ✅ in the repo, asserted by CI on the built `.app` |
| **Tunnel proven on hardware** | ✅ **2026-09-03** — iPhone 12, iOS 26.6, Singapore, real traffic over `utun5` |
| Registered device | ✅ iPhone 12, UDID `<UDID iPhone — lihat catatan operator>` |
| Apple Distribution certificate | ✅ `Apple Distribution: PT. STACOPA AVANGARD RAYA (8HSUX5T86H)`, in the Mac's login keychain |
| First `.ipa` | ✅ 2.0 MB, signed for distribution, every CI assertion green |
| App Store Connect app record | ✅ created; availability restricted to **Indonesia only** |
| TestFlight build `1.0 (1)` | ✅ uploaded 2026-09-03, compliance answered, **Ready to Submit** |
| Internal testers | ✅ **already there** — the group "Internal" has a tester whose state is `INSTALLED`, so a distribution build is on a device. Verified against the API 2026-09-04; the earlier "none added yet" here was simply never checked |
| Tunnel on a **distribution** build | ✅ **2026-09-04** — build `1.0 (1)` from TestFlight, Singapore **and** Germany, operator-reported. Not instrumented, unlike the development test; see `AGENTS.md` for what that does and does not establish |
| External TestFlight | ⛔ `externalBuildState=BETA_REJECTED`, with a `betaAppReviewSubmissions` record submitted 2026-09-03 11:06 WIB. Nobody remembers submitting it, no external group exists, and the API exposes neither who submitted nor why it was refused — that lives only in Resolution Center. It blocks nothing: internal testing is unaffected, and the state is per build |

### What the first Mac session found — 2026-09-03

Everything below was discovered by running the release path for the first time.
Three of them are fixed in the repo; the rest is state that lives in Apple's
systems and cannot be read from a checkout.

**Three bugs that had never fired, because nothing had ever archived.**
`ios-release.yml` is the only thing that archives, and it has never run — the
repo holds none of its five secrets, so it fails at the credential step first.

| Symptom | Real cause | Fixed in |
|---|---|---|
| `unable to spawn process '/usr/bin/env' (No such file or directory)` | Not a missing binary. `posix_spawn` returns ENOENT for a missing **working directory** too, and `$(BUILD_DIR)` moves between `build` and `archive` | PR #21 — `Scripts/build-wireguard-go.sh` |
| `error: exportArchive Copy failed`, and nothing else | GNU rsync ahead of openrsync on `PATH`. The `brew install rsync` the build needs is what breaks the export | PR #21 — `PATH="/usr/bin:$PATH"` on that step |
| `ITMS-90474` orientations, `ITMS-90592` export compliance | Both rejected the first upload. iPad needs all four orientations; `ITSAppUsesNonExemptEncryption: YES` without a compliance code is refused | PR #23 |

**Three things the instructions got wrong, now corrected in place.**

- `xcodebuild -allowProvisioningUpdates` does **not** register a new device. It
  only refreshes profiles for devices already registered. Xcode.app registers;
  the CLI does not. Register the UDID once by hand at
  [Devices](https://developer.apple.com/account/resources/devices/list).
- `TARGETED_DEVICE_FAMILY` at **project** level is ignored — XcodeGen writes
  `"1,2"` into every iOS target, and target-level wins. It must be repeated in
  each shipping target.
- A **cable is not required** to build, install or archive. This iPhone was
  reachable over `transportType: localNetwork` the whole morning. Check
  `xcrun devicectl list devices --json-output`, not `xctrace list devices`
  (which reported "Offline" while the device was working) and not
  `system_profiler SPUSBDataType` (which showed nothing even over USB).

**How to read the tunnel's logs from a Mac.** The extension's own `Logger` lines
are **invisible** to `idevicesyslog` — the legacy syslog relay does not carry
`os_log` from NetworkExtension processes, so the PID exists with zero output.
`log stream` has no device option at all on macOS 26. What works is watching the
system daemons instead:

```bash
brew install libimobiledevice
idevicesyslog -u <UDID> -e backboardd,locationd,SpringBoard,mediaserverd,symptomsd,dasd \
  | grep utun
```

7,191 lines named `utun5` and no other tunnel interface. The line that settles
it is a *completed* transaction, not merely a routed one:

```
CKDFetchRecordZoneChangesURLRequest host=gateway.icloud.com
  i=utun5 tlsVersion=TLSv13 protocol=h3
  responseBodyBytes=132 err=F transactionDuration=0.290
```

`err=F` with a response body means the tunnel carries traffic both ways — not an
interface standing over a dead path, which is exactly the P0 bug
`PacketTunnelProvider.swift` was written to avoid.

### Still open after that session

- ⬜ **The tunnel has not been verified on a *distribution* build.** What was
  proven is a development build. TestFlight ships a different signature —
  `get-task-allow = false`, Apple Distribution rather than Apple Development —
  and entitlement problems of exactly that class do not appear in development
  builds.
- ✅ **Internal testers.** The group "Internal" has a tester whose state is
  `INSTALLED`, so a distribution build is on a device. Verified against the API
  2026-09-04; the "nobody is on the build yet" that stood here was never checked.
- ✅ **Reviewer sign-in credentials are known.** Email
  `<akun demo reviewer — lihat catatan operator>`, proven end to end against production
  2026-09-03 and verified in App Store Connect 2026-09-04:
  `demoAccountRequired: true` with the name set on **both**
  `betaAppReviewDetail` (TestFlight) and `appStoreReviewDetail` (App Store).
  Those are separate resources and each carries its own copy — filling one does
  not fill the other. The code is stored server-side as a sha256 hash and can
  never be read back, only rotated, so write it down at the moment you set it
  and update both ASC records in the same breath.
- ✅ **App Store Connect API key.** Created 2026-09-03: role **App Manager**,
  key id `<ASC Key ID>`; the `.p8` lives outside every repo. It is all three ASC
  secrets `ios-release.yml` needs — but the key was never what stopped that
  workflow. Actions billing is, and the three repo secrets are still unset.
- ✅ **Screenshots.** Eight delivered under `APP_IPHONE_65`, every one
  `COMPLETE`. Verified against the API 2026-09-04. They had to come off a
  physical device: the Simulator cannot show a connected state at all — a
  packet-tunnel extension does not run there, and the only target that *builds*
  for the Simulator (`AvangardVPNDeviceTest`) is the one with the extension
  removed.
- ⬜ **`409` on registering a second device.** Provisioning Singapore on a
  second device failed with `The server rejected the request (HTTP 409)`. That
  is the fallback string in `APIClient.swift:27`, so the error **code** was
  neither `device_limit_reached` nor anything else mapped — worth finding out
  which, because the message a user sees is currently a raw status.
- ⬜ **The layout does not use a 6.9" screen.** On an iPhone 17 Pro Max the
  content stays centred and small, leaving large empty bands. Not a bug; it
  will show in App Store screenshots.

### Step 1 — Go 1.21, and only 1.21

⛔ **Not `brew install go`.** That installs the newest Go, and the wireguard-go
bridge patches the Go runtime so its monotonic clock follows boot time — the
thing that keeps WireGuard's handshake and keepalive timers alive while the phone
sleeps. The patch was written against Go 1.17-1.21, and the failure it prevents
is a tunnel that dies silently overnight.

Homebrew cannot help: `go@1.21` is a **disabled** formula, so the install is
refused. Use the official archive — go.dev keeps every release ever shipped:

```bash
curl -LO https://go.dev/dl/go1.21.13.darwin-arm64.tar.gz   # darwin-amd64 on Intel
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.13.darwin-arm64.tar.gz
/usr/local/go/bin/go version    # expect go1.21.13
```

⛔ **Extracting it is only half the job.** The bridge resolves `go` and `rsync`
from Xcode's build PATH, and a GUI-launched Xcode gets
`/usr/bin:/bin:/usr/sbin:/sbin` and nothing else. Put both tools somewhere that
PATH can reach, then tell the GUI about it:

```bash
brew install rsync                                   # GNU rsync; see Step 2
sudo ln -s /usr/local/go/bin/go    /usr/local/bin/go
sudo ln -s /opt/homebrew/bin/rsync /usr/local/bin/rsync

launchctl setenv PATH "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
```

Order matters: `/usr/local/bin` has to come **before** `/usr/bin`, or `rsync`
still resolves to macOS's openrsync and the toolchain copy fails with `Error 20`.

⚠️ Two limits worth knowing before you lose an hour. `launchctl setenv` does not
survive a reboot — make it a LaunchAgent if you want it permanent. And **Xcode
must be restarted** to inherit it, because a running Xcode keeps the PATH it was
launched with.

A CLI build (`xcodebuild` from your shell) inherits your shell's PATH instead, so
it can pass while the GUI still fails on the same tree. Proving the toolchain and
proving the GUI's view of it are two separate checks; do both.

### Step 2 — generate and open

```bash
brew install xcodegen rsync    # rsync: macOS ships openrsync, which the bridge's Makefile fails on
                               # installing it is necessary but not sufficient — Step 1's
                               # symlink is what puts it on Xcode's build PATH
git pull
xcodegen generate && open AvangardVPN.xcodeproj
```

### Step 3 — run

Scheme **AvangardVPN** — *not* `AvangardVPNDeviceTest`, which deliberately omits
the tunnel extension and can never connect. Pick your iPhone, press **Run**, sign
in, choose a region, press **Connect**.

The app talks to production by default, so you need a real account at
`https://app.avangardvpn.com`.

### What success looks like

The orb is the connection state: **indigo → amber while handshaking → emerald
once traffic flows**, with the telemetry strip counting bytes. Nobody has seen
the amber and emerald phases run — they are pinned by tests, not by observation.

Then the honest checks, in order:

1. Settings → VPN shows one **AvangardVPN — <region>** entry (one, not a pile)
2. A "VPN" badge in the status bar
3. `https://ifconfig.me` in Safari returns the node's IP, not your ISP's
4. Lock the phone for half an hour, come back — still connected. That is the
   boot-time clock patch doing its job, and the reason Go is pinned

### If it fails

Read the extension's log first. It is a separate process, so Xcode's console
does not show it: open **Console.app**, select the iPhone in the sidebar, and
filter on subsystem `com.avangard.vpn.network-extension`.

| Symptom | Cause |
|---|---|
| `[ -n "" ]` followed by `make: *** [.../goroot/.prepared] Error 1` | **This is what a `go` Xcode cannot see actually looks like** — `Makefile:27` runs `go env GOROOT 2>/dev/null`, so `command not found` never reaches you. Xcode's build PATH is not your shell's. Redo Step 1's symlink + `launchctl setenv`, then restart Xcode. **Not** a missing install |
| `make: Error 20` while copying the toolchain | `rsync` resolved to macOS's openrsync. `brew install rsync` alone does not fix a GUI build: `/opt/homebrew/bin` is not on Xcode's PATH. Symlink it into `/usr/local/bin` and put that **before** `/usr/bin` (Step 1) |
| No provisioning profile found | A capability is missing on one of the App IDs — most often App Groups enabled but with **zero** groups bound. `Enabled App Groups (1)`, not `(0)` |
| `saveToPreferences` fails | The **app** target is missing `packet-tunnel-provider`. It is not a copy-paste slip that the app carries the extension's entitlement — `NETunnelProviderManager` is gated on it at the calling side too |
| Connects, then nothing loads | Look for `startTunnel` in Console. A handshake that never completes points at the peer config, not at the app |
| Works, then dies while the phone sleeps | The Go version. Go back to step 1 |
| `error: exportArchive Copy failed`, and nothing else | GNU rsync ahead of openrsync on PATH. Xcode's IPA packaging only accepts openrsync's arguments, so the `brew install rsync` above breaks the export. Run it as `PATH="/usr/bin:$PATH" xcodebuild -exportArchive …`. The real message is in the `.xcdistributionlogs` bundle whose path xcodebuild prints one line earlier, never on stdout |
| `unable to spawn process '/usr/bin/env' (No such file or directory)` from `WireGuardGoBridge` | Not a missing binary — `posix_spawn` returns ENOENT for a missing **working directory** too, and Xcode names the wrong file. The checkout was not where the target looked. Fixed by `Scripts/build-wireguard-go.sh`; see its header |

### You do not need TestFlight for this

`.github/workflows/ios-release.yml` builds and uploads without a Mac, and it is
how releases will work — but it is the slower way to answer *this* question:
15-20 minutes per attempt, and no device log to read when it fails.

⚠️ It has also **never been run**, and cannot be until its five secrets exist, so
its first run is its own first test. Prove the tunnel over a cable first: two
unproven things at once is what makes a failure hard to place.

## Trying it on a real iPhone (no paid account)

⚠️ **Superseded for day-to-day use.** The enrolment is paid, so the section above
is the real path. This one stays because `AvangardVPNDeviceTest` is still the
only host that can run the test suite on a Simulator — deleting the target takes
the tests with it — and because a free Personal Team remains the fallback if the
paid account is ever unavailable.


Everything built so far — sign-in, region provisioning, the UI — uses **no paid
capability**. App Groups and NetworkExtension belong to the tunnel (P3), which
isn't here yet. So the `AvangardVPNDeviceTest` scheme runs the real app on a
real iPhone signed with a **free Apple ID**:

```bash
xcodegen generate && open AvangardVPN.xcodeproj
```

In Xcode: scheme **AvangardVPNDeviceTest** → target → Signing & Capabilities →
*Automatically manage signing* → Team = **your own Personal Team** → select
your iPhone → Run.

Once signing is set up once, re-installing is faster from the CLI — which
matters because free-signed builds expire every 7 days:

```bash
DEVELOPMENT_TEAM=<your-personal-team-id> Scripts/install-on-device.sh
```

It picks the connected device itself, builds, checks the bundle carries no paid
entitlement, and installs. Find your team id with:

```bash
security find-identity -v -p codesigning
security find-certificate -c "<the Apple Development line>" -p \
  | openssl x509 -noout -subject     # OU=... is the team id
```

Two one-time steps on the phone:

- **Settings → Privacy & Security → Developer Mode** → on. iOS 16+ refuses to
  run self-built apps without it, and turning it on reboots the phone. Until
  then the device shows as *available* rather than *connected* and builds fail
  with `Developer Mode disabled`.
- After the first install: **Settings → General → VPN & Device Management** →
  trust the developer certificate.

A **Personal Team is separate from any organisation** the same Apple ID belongs
to — different team id, its own certificate, its own App IDs. Signing with it
registers nothing against the organisation's account.

What works: sign-in, choosing a region, a **real keypair generated on the
phone**, the assembled config, account + quota screens.

⚠️ **Connect does not work in this scheme**, and that is not the same as it
being unimplemented. `AvangardVPNDeviceTest` deliberately omits the tunnel
extension and the App Group, because a free Personal Team cannot sign either.
The tunnel is built (P3); it needs the paid entitlement to run.

Verified on real hardware 2026-07-28: builds, signs under a Personal Team, and
installs onto an iPhone 12 (iOS). Not yet exercised by a person end-to-end —
in particular, opening the magic link from a real inbox and having the app pick
the session up by polling has still only been tested via scripts.

Two things to know:

- **Free-signed builds expire after 7 days.** Re-run from Xcode to renew.
- The bundle id is `com.avangard.vpn.devtest`, deliberately **not** the
  production `com.avangard.vpn`. App IDs are globally unique across Apple
  Developer accounts, so letting a personal team claim the production id risks
  blocking the real account from registering it later.

By default the app talks to production, so you need an account there. To point
it at a backend on your Mac instead, add `AVANGARD_API_BASE=http://<mac-lan-ip>:3000`
to the scheme's environment variables (Product → Scheme → Edit Scheme → Run →
Arguments) with the phone on the same Wi-Fi. That variable is DEBUG-only and
compiled out of Release builds.

## TestFlight (the Mac-free path)

`.github/workflows/ios-release.yml` builds a signed `.ipa` on a macOS runner and
uploads it to TestFlight. **Nobody needs a Mac** — but a physical iPhone is not
optional: a packet-tunnel extension cannot run in the Simulator, so TestFlight is
the only way to watch the tunnel actually come up.

Internal testers need no Beta App Review, so an uploaded build is installable
within minutes.

Every step below can be done from Windows (WSL or Git Bash). **Do not paste any
of these values into a chat, a commit, or an issue** — `gh secret set` reads from
a file so the value never reaches your shell history either.

**Where this actually stands, 2026-09-04.** The first build reached TestFlight
by hand from the Mac (Xcode Organizer), not through this pipeline — which has
still never run, and now cannot:

| Step | |
|---|---|
| 1. Distribution certificate | ✅ exists, created through Xcode on the Mac. The `.p12` for CI has **not** been exported yet |
| 2. App Store Connect API key | ✅ **created** — key `<ASC Key ID>`, App Manager. The `.p8` lives outside this repo and is never committed |
| 3. Repository secrets | ⬜ none set — **and deliberately so**, see below |
| 4. The app record | ✅ created, Indonesia-only |
| 5. Ship it | ⬜ never run |

⛔ **GitHub Actions has no included minutes left.** Every run since 2026-09-03
dies in 3 seconds without starting:

    The job was not started because recent account payments have failed
    or your spending limit needs to be increased.

So setting the five secrets buys nothing until billing is fixed. The pipeline is
not broken; it is unfunded. Until then the release path is **local on a Mac**,
which needs no Actions at all: `xcodebuild archive` → `-exportArchive` (with
`PATH="/usr/bin:$PATH"` on that step) → `xcrun altool --upload-app`, all three
authenticated with the same `.p8` via `-authenticationKeyPath` / `--apiKey`.

The key is also what `Tools/asc.rb` uses to read and write App Store Connect
metadata from a terminal — see [App Store Connect from a
terminal](#app-store-connect-from-a-terminal).

### 1. Distribution certificate

Apple normally has you make this in Keychain Access. `openssl` does the same job:

```bash
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ios_distribution.key \
  -out ios_distribution.csr \
  -subj "/emailAddress=you@example.com/CN=PT Stacopa Avangard Raya/C=ID"
```

Upload `ios_distribution.csr` at **Certificates, Identifiers & Profiles →
Certificates → + → Apple Distribution**, then download the `.cer` and convert:

```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -legacy \
  -inkey ios_distribution.key -in distribution.pem -out distribution.p12
base64 -w0 distribution.p12 > distribution.p12.base64
```

⚠️ **`-legacy` is load-bearing.** OpenSSL 3 defaults to an AES-256 PKCS#12 that
macOS `security import` cannot read, and it fails with a MAC-verification error
that reads like a wrong password. `-legacy` writes the older format macOS
accepts.

Keep `ios_distribution.key` somewhere safe and out of the repo. Losing it means
revoking the certificate and starting over; Apple allows only a few at a time.

### 2. App Store Connect API key

**Users and Access → Integrations → App Store Connect API → +**, role **App
Manager** (Admin also works). Note the **Key ID** and the **Issuer ID**, and
download the `.p8` — App Store Connect lets you download it exactly once.

```bash
base64 -w0 AuthKey_XXXXXXXXXX.p8 > asc_key.base64
```

### 3. Repository secrets

```bash
R=Stacopa-Avangard/avangardvpn-ios
gh secret set IOS_DIST_CERT_P12_BASE64 -R $R < distribution.p12.base64
gh secret set ASC_API_KEY_P8_BASE64    -R $R < asc_key.base64
gh secret set IOS_DIST_CERT_PASSWORD   -R $R   # the -export password from step 1
gh secret set ASC_API_KEY_ID           -R $R
gh secret set ASC_API_ISSUER_ID        -R $R
```

Then delete the local `.p12`, `.base64` and `.p8` files.

### 4. The app record

**App Store Connect → Apps → + → New App**: iOS, bundle ID `com.avangard.vpn`,
any SKU. The upload has nowhere to land without it.

⚠️ The App Store **name** is globally unique across all of Apple's catalogue, so
it is the one field that can be refused. It is independent of
`CFBundleDisplayName` and can be changed later.

### 5. Ship it

Actions → **TestFlight** → *Run workflow*, or push a `v*` tag.

The workflow rejects a run with missing secrets by name rather than failing
somewhere inside `xcodebuild`, and it unpacks the exported `.ipa` to assert the
privacy manifests, the icon key and the export-compliance key are really in it —
those three come back from App Store Connect as an email minutes after an upload,
which is a slow way to learn about a packaging mistake.

Afterwards, in App Store Connect: answer the **export compliance** questionnaire
(see [above](#itsappusesnonexemptencryption-true)), then **TestFlight → Internal
Testing**, add yourself, and install from the TestFlight app on the iPhone.

### Cost

A run is roughly **130 minutes of Actions quota** — macOS runners bill at a 10x
multiplier, against 2,000 free minutes a month on the org's plan. Roughly fifteen
cold runs a month. That is why this workflow is manual and tag-driven rather than
running on every push.

## App Store Connect from a terminal

`Tools/asc.rb` signs an ES256 JWT with the App Store Connect API key and calls
the REST API. It exists because the console is slow to audit and because the CI
that used to do this cannot run — see [TestFlight](#testflight-the-mac-free-path).

```bash
export ASC_KEY_PATH=/path/to/AuthKey_<ASC Key ID>.p8   # never in this repo
export ASC_KEY_ID=<ASC Key ID>
export ASC_ISSUER_ID=…                               # Users and Access → Integrations
export ASC_APP_ID=6808064676

ruby Tools/asc.rb "/v1/apps/$ASC_APP_ID"                     # read
ruby Tools/asc.rb "/v1/appInfos/<id>" PATCH '{"data":…}'     # write
```

Three things that cost time to find out:

- **PyJWT and `cryptography` are not installed** in macOS's system python3, so
  the signer is Ruby, whose stdlib `openssl` is. OpenSSL emits an ECDSA
  signature in **DER**; a JWT wants raw `r||s`, 64 bytes. `asc.rb` unpacks it
  with `OpenSSL::ASN1.decode` — a JWT that "looks right" but fails with a 401 is
  usually this.
- **`relationships.*.data` is empty unless you ask for it.** `GET /v1/appInfos/<id>`
  reports no category even when one is set; `?include=primaryCategory` reports
  it. A PATCH that returns 200 has worked — verify with `include`, not without.
- **macOS `base64` rejects a filename argument.** `base64 -d file.b64 > out` is
  GNU syntax; here it prints `invalid argument` and writes nothing, while the
  shell's `>` still creates the file. The result is a 0-byte key that looks like
  success. Use `base64 -d < file.b64` and check with `openssl pkey -in … -noout`.

### Metadata state, 2026-09-04

Filled through the API, all still `PREPARE_FOR_SUBMISSION` — nothing has been
submitted, and `GET …/appStoreVersionSubmission` returns 404:

| Field | |
|---|---|
| `privacyPolicyUrl` | ✅ `https://app.avangardvpn.com/privacy`. ⚠️ `avangardvpn.com/privacy` is **404** — only the `app.` host serves it, and that is the host the app itself links to |
| `primaryCategory` | ✅ `UTILITIES`. Of 100 VPN apps on the Indonesian App Store the split is 46 Utilities / 44 Productivity, so there is no "correct" answer from population — but NordVPN and Proton VPN both sit in Utilities, while the Productivity side is mostly free "Fast VPN Proxy" listings |
| `ageRating` | ✅ `FOUR_PLUS`. Everything `NONE`/`false`, including `unrestrictedWebAccess` — this app embeds no browser and renders no arbitrary web content. `unrestrictedWebAccess` and `ageAssurance` are **required** and are **booleans**; omitting either fails the PATCH with `ENTITY_ERROR.ATTRIBUTE.REQUIRED` |
| description | ✅ reworded. Two lines promised bypassing local network restrictions and "disguising" browsing on office and campus networks. Against a `4+` declaration that says the opposite, the declaration is what loses |
| demo account | ✅ **set** — verified 2026-09-04: `demoAccountRequired: true`, name `<akun demo reviewer — lihat catatan operator>`, on `appStoreReviewDetail` **and** on `betaAppReviewDetail`, which is a separate resource for TestFlight. The code stays out of this repo |

⚠️ Build `1.0 (1)` carries none of this app's newer screens and expires
**2026-12-01**. Whatever is submitted for review must be a build that contains
the data disclosure screen.

## Debugging on a real device from a Mac

Measured on an iPhone 12 / iOS 26.6.1 / Xcode 26 on 2026-09-04. The short
version: you can install, launch and read files, but you cannot see the screen
and you cannot read the app's own log.

| Need | What works |
|---|---|
| Build, install, launch, uninstall | `devicectl` — over USB **or** Wi-Fi |
| Read files out of the app container | `devicectl device copy from --domain-type appDataContainer --domain-identifier com.avangard.vpn --source Library/Preferences/com.avangard.vpn.plist` — no Developer Disk Image needed, and the way to prove a `UserDefaults` write actually landed |
| System daemon logs | `idevicesyslog -u <UDID>` — needs USB. 15,000 lines in 4 seconds |
| See the screen | ⛔ `idevicescreenshot` fails with `Could not start screenshotr service: Invalid service`. libimobiledevice 1.4.0 cannot mount the personalised DDI iOS 26 uses. Workaround: press **Side + Volume Up** on the phone and pull the PNG from `/DCIM/100APPLE` with `afcclient`, diffing the listing to find it. The files are `.PNG`, **uppercase** |
| The app's own `Logger` lines | ⛔ nothing. `os_log` is not carried by the legacy syslog relay — not for the tunnel extension, and not for the app either. 0 of 6,231 captured lines mentioned the app |
| Tap the screen | ⛔ no path. There is no XCUITest target in this project |

⚠️ **`system_profiler SPUSBDataType` does not exist on macOS 26.** It was renamed
`SPUSBHostDataType`, and the old name exits quietly with no output — which reads
exactly like "no device attached". The earlier note in this file blaming Apple
for that silence was wrong. Use `idevice_id -l` (empty means no USB) and
`transportType` from `devicectl list devices --json-output`.

⛔ **gstack's `/ios-qa` DebugBridge does not fit this project**, checked again
against gstack 1.79.0.0. Its generator (`scripts/gen-accessors.ts:119`) matches
`@Observable` with a regex and nothing else; `AuthStore`, `ProvisioningStore` and
`TunnelStore` are all `ObservableObject` + `@Published`, so it emits zero
accessors. It also assumes a SwiftPM app manifest, and this app is an
XcodeGen-generated `.xcodeproj`. Converting to `@Observable` would raise the
deployment target from **16.0 to 17**, which is a product decision, not a
testing one.

⚠️ `xcodebuild test -scheme AvangardVPN` fails with *"Scheme AvangardVPN is not
currently configured for the test action"*. The test action lives on the
`AvangardVPNDeviceTest` scheme, whose bundle id `com.avangard.vpn.devtest` was
built for a free Personal Team — running it under the organisation team would
register a new App ID on the paid account.

## Icon

`App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, generated
by [`Tools/render-app-icon.swift`](Tools/render-app-icon.swift):

```bash
swift Tools/render-app-icon.swift \
  App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

It draws the brand kit's "A" monogram — the exact `pathData` from Android's
`ui/src/main/res/drawable/ic_launcher_foreground.xml`, in its native 250×250
viewport — on Android's launcher gradient (`#312E81` → `#0D6EFD`, top-left to
bottom-right). Nothing is upscaled: the glyph is vector all the way to the
1024 raster, which is why the script exists instead of a checked-in export from
a design tool.

Two things it does that are not obvious, and that a hand-made replacement would
get wrong:

- **No alpha channel** (`noneSkipLast`). App Store Connect rejects an app icon
  that carries one.
- **The glyph is 62% of the canvas, where Android's reads as ~78%.** Android's
  is a 108dp adaptive icon of which only 72dp is ever visible, so the same
  optical weight needs a smaller fraction on iOS, where the whole 1024 shows.

The shield is a different mark and is not the app icon on either platform: it
is the splash and the sign-in screen (`SplashView`, `ShieldMark`).

One thing the catalog does **not** do on its own, found by the CI check added
alongside the privacy manifests: on Xcode 26 actool writes `CFBundleIconName`
only inside `CFBundleIcons` > `CFBundlePrimaryIcon` and leaves the **top level**
empty — and the top-level key is the one **ITMS-90713** is about. `project.yml`
pins it explicitly on both app targets. Keep its value equal to
`ASSETCATALOG_COMPILER_APPICON_NAME`.

## Privacy manifest and export compliance

App Store requirements that say nothing about how the app behaves and everything
about whether a build can be uploaded at all. Both were done without an Apple
account; neither was ever waiting on the enrolment.

### `PrivacyInfo.xcprivacy` — one per bundle, not one per project

- [`App/Resources/PrivacyInfo.xcprivacy`](App/Resources/PrivacyInfo.xcprivacy)
- [`Tunnel/Resources/PrivacyInfo.xcprivacy`](Tunnel/Resources/PrivacyInfo.xcprivacy)

Mandatory since May 2024, and its absence is not a warning: App Store Connect
answers the upload with **ITMS-91053** and the build never becomes submittable.

Two files, because Apple scans each **binary** and the two give different
answers:

| | App | Tunnel extension |
|---|---|---|
| Collects | email, account id, device UUID — all linked to the user, none for tracking | **nothing** |
| Required-reason API | `UserDefaults` (`CA92.1`) — the active region code | system boot time (`35F9.1`) |

The extension's is the surprising one. Nothing in `Tunnel/Sources` asks for the
boot time — **wireguard-go** does. Its handshake and keepalive timers run on a
monotonic clock, and the Go runtime's `nanotime` on Darwin is
`mach_absolute_time`. Apple's scanner reads symbols, not intent, so grepping our
Swift and finding nothing is not evidence that the declaration is stale.

Deliberately **not** declared: `deviceName`. On iOS 16+ — and 16.0 is the floor
here — `UIDevice.current.name` returns the model string without a special
entitlement, so what reaches the server is "iPhone" and it identifies nobody.

### Export compliance — answered in App Store Connect, not in the plist

⚠️ **There is deliberately no `ITSAppUsesNonExemptEncryption` key.** It used to
be set to `true` in [`project.yml`](project.yml), so App Store Connect would
stop asking per build. App Store Connect rejects that:

```
ITMS-90592: Invalid Export Compliance Code. The export compliance key value []
in the app's Info.plist doesn't match the key value of the app's export
compliance documentation.
```

`YES` in the plist claims documentation is already on file, so Apple then wants
`ITSEncryptionExportComplianceCode` beside it — and that code exists only once
App Encryption Documentation is filed in App Store Connect. It is not filed
here, and per the CCATS row below probably never needs to be.

**The answer has not changed; only where it is given.** True is the accurate
answer, not the cautious one. The exemption apps normally claim is "only uses
encryption available in the operating system", which fits an app whose crypto is
HTTPS through `URLSession`. It does not fit one that embeds wireguard-go's own
ChaCha20-Poly1305, Curve25519 and BLAKE2s. Nor do the others — authentication,
DRM, medical. A VPN is the textbook non-exempt case.

**What to answer in App Store Connect** (used 2026-09-03; the questionnaire
returns per build until an answer is carried forward):

| Question | Answer |
|---|---|
| Does your app use encryption? | **Yes** |
| What type of encryption algorithms does your app implement? | **"Standard encryption algorithms instead of, or in addition to, using or accessing the encryption within Apple's operating system"** |
| Is your app going to be available for distribution in France? | **No** |

The middle one is where this goes wrong most easily. "Only encryption within
Apple's operating system" is the tempting answer and it is **false** here —
wireguard-go carries its own implementation into the `.appex`. "Proprietary" is
equally false: every primitive is an IETF RFC.

⚠️ The France answer is only accurate because **Availability was restricted to
Indonesia first**. A new app record defaults to all 175 territories, France
included. Set the territories *before* answering, or the answer is a false one —
and a `Yes` obliges a separate cryptography declaration to **ANSSI**.

⚠️ **The declaration opens an obligation — a smaller and later one than the
first version of this section claimed.** Checked against BIS and Apple on
2026-09-02:

| | Status |
|---|---|
| Encryption registration (**ERN**) | **Gone.** BIS removed it in its rule of 29 March 2021 — nothing to register before exporting. |
| **CCATS** | **Probably not needed.** Apple requires one only for *proprietary* algorithms no standards body accepts. Every primitive here is an IETF RFC — ChaCha20-Poly1305 (8439), Curve25519 (7748), BLAKE2s (7693) — Apple's "industry standard algorithm, not provided within the Apple operating system" row. |
| **France declaration** | Only if the app is sold on the French App Store. Availability was set to **Indonesia only** on 2026-09-03, so nothing is owed — but that is a setting someone can widen later, and widening it revives this. |
| **Annual self-classification report** | **Retrospective, not a precondition.** ECCN 5D002 under License Exception ENC §740.17(b)(1), due 1 February for the *previous* calendar year and not owed at all for a year with no exports. CSV, 12 columns, to `crypt@bis.doc.gov` and `enc@nsa.gov`. |

So the only export step between here and a release is **App Store Connect's own
questionnaire**. US export rules apply at all because the App Store distributes
from the US — an Indonesian developer account does not change that.

The CCATS row is the one judgement worth a professional opinion: if anyone reads
wireguard-go's protocol as proprietary rather than standard, a CCATS is a BIS
submission with a waiting period attached.

`AvangardVPNDeviceTest` carries neither the key nor the obligation: it is a
free-signed local build that never reaches App Store Connect.

## Design

The interface is a **port of the Android client's design system**, not a
separate iOS look. `App/Sources/Design/Theme.swift` mirrors Android's
`ui/theme/Theme.kt` value for value: the `#090B12` ground, the indigo → amber →
emerald ramp that the connection phase drives, the glass treatment, the ambient
wash behind every screen.

Two rules follow from that, and both have already been broken once:

- **A palette change lands on both clients or neither.** iOS used to paint its
  controls `#0D6EFD` under a comment claiming that was Android's primary. It is
  not — it is the launcher-icon blue, and Android's UI primary is `#6366F1`.
  The two clients looked like different products for it.
- **Byte counts are base 1000** (`Core/ByteFormat.swift`), matching the backend
  and the portal. iOS used to call `ByteCountFormatter` with `.binary`, so a
  10 GB plan read as "9.3 GB" here and "10.0 GB" everywhere else.

The shell is a `ZStack`, not a `TabView`: the ambient wash has to sit behind
everything and the glass nav bar has to float over it, and a system tab bar
paints an opaque strip over the bottom glow.

## Tests

`AvangardVPNTests` exercises the real API client against a backend running
locally from `Stacopa-Avangard/avangardvpn-server` — no production traffic, no emails
sent (dev logs the magic link to stdout instead).

```bash
# terminal 1 — in the wireguard-dashboard checkout
cd backend && cp .env.example .env   # fill in throwaway secrets, RESEND_API_KEY empty
pnpm install && pnpm seed:admin -- --email=ios-test@avangard.local --name="iOS Tester"
pnpm dev 2>&1 | tee /tmp/backend.log

# terminal 2 — here
BACKEND_LOG=/tmp/backend.log Scripts/run-auth-tests.sh
```

The script does what a test inside the Simulator can't: it reads the magic-link
token out of the backend log and "clicks" the link, so the test can then claim
the session exactly as the app would.

To poke at the signed-in UI by hand without typing an address and opening a
mail client:

```bash
BACKEND_LOG=/tmp/backend.log Scripts/run-dev-session.sh
```

It prepares a verified session the same way and launches the app already signed
in (the app claims it on launch — DEBUG only, see `AuthStore.restore`). Set
`AVANGARD_DEV_TAB=account` to open straight onto the Account screen.

Two things about how these run, both deliberate:

- **No `CODE_SIGNING_ALLOWED=NO`.** The Keychain refuses to store anything for
  an unsigned bundle (`errSecMissingEntitlement`, -34018), so the tests rely on
  the ad-hoc signature Xcode gives Simulator builds. Still no Apple account.

  ⚠️ This applies to **running the app in the Simulator too**, not only to the
  tests, and it fails in a way that does not look like a signing problem: the
  build succeeds, the app launches, and sign-in ends on *"Couldn't save your
  session to the Keychain."* Drop the flag and rebuild. CI can pass it because
  CI only compiles and runs tests that do not touch the Keychain.
- Config reaches the tests as **scheme environment variables** fed from build
  settings. The `TEST_RUNNER_`-prefix trick only works for UI-test runners.

Without `AVANGARD_API_BASE` set, the network tests skip themselves, so a plain
`xcodebuild test` (and CI's compile-check) stays green with no backend around.

## Roadmap

- [x] **P0** — repo + XcodeGen scaffold (app + tunnel stub) + CI compile-check
- [x] **P1** — Auth: poll-login (`/auth/poll`), Keychain token store, auto-refresh
      on 401, sign-in UI. Verified end-to-end against a local backend.
- [x] **P2** — Provisioning: Curve25519 keygen (CryptoKit), `POST /api/me/devices/regions`,
      local config assembly, region picker. Verified end-to-end against a local backend.
- [x] **P3** — Tunnel: `PacketTunnelProvider` + WireGuardKit (wireguard-go build).
      **Code complete and CI-green, still not exercised on a phone.** The
      entitlement that blocked it is now available — the enrolment is paid and
      both App IDs are configured — so this is no longer waiting on anything but
      someone doing it. Until then the connect path is unverified, and the
      orb's amber and emerald phases have never been watched. See
      [Running it on a real iPhone](#-running-it-on-a-real-iphone-paid-account--start-here).
- [x] **P4** — SwiftUI UI: Connect / Account tabs, region picker sheet, quota
      meter, shared theme tokens. The connect control is live.
- [x] **P4.5** — Design parity with Android: the "security console" system is
      now a port rather than a lookalike — same palette, same phase→accent ramp,
      same orb, glass, floating nav and telemetry strip. See *Design* below.
- [ ] **P5** — Always-on (`NEOnDemandRule`). IPv6 dual-stack (`assignedIpv6`) is
      **already done** — `TunnelConfig` routes `::/0` only when the region
      assigns a v6 address. On-demand is deliberately off (see
      `VPNConfiguration.apply`): it is a product decision on a metered plan, and
      it would reconnect after a user had deliberately disconnected.
- [~] **P6** — TestFlight distribution. **Build `1.0 (1)` is on TestFlight as of
      2026-09-03**, but it got there by hand from a Mac, not through the
      pipeline — `ios-release.yml` has still never run. The app record and the
      export questionnaire are done; what is left is the App Store Connect API
      key and the repository secrets, plus adding an internal tester so somebody
      can actually install it.

### Still missing, and why it matters

- ✅ **The tunnel is proven on both signatures.** A development build carried
  real system traffic on an iPhone 12 on 2026-09-03, watched from the outside
  (`utun5`, completed transactions, `err=F`). The narrower question that
  replaced it — whether it also comes up under an Apple Distribution signature
  with `get-task-allow = false` — was answered on 2026-09-04: build `1.0 (1)`
  installed from TestFlight connected to **Singapore and Germany**, reported by
  the operator. ⚠️ That second one is a person's report, not a captured log.
  It is enough to close the entitlement-class risk, because a failure of that
  class stops the tunnel coming up at all; it is not enough to diagnose a
  subtler fault. Re-run the `idevicesyslog` recipe if one is ever suspected.
- **Nothing blocks review any more on the account side**: in-app account
  deletion (Guideline 5.1.1(v)), sign-in by code for the reviewer, and in-app
  privacy/terms links all landed with P4.5.
- **Nothing blocks upload any more either**: the app icon landed with P4.5, and
  the privacy manifest and export-compliance declaration with the PR after it.
  All three answer an upload *rejection* rather than a review note, and none of
  them needed an Apple account — which is precisely why the earlier wording here
  ("the enrolment is the remaining gate") was wrong and worth correcting: it
  would have let two of them sit unnoticed until a build bounced.
- **One open item is paperwork rather than code, and it is smaller than it
  first looked here.** Declaring non-exempt encryption puts us under License
  Exception ENC, whose annual ECCN 5D002 report covers **the previous year's
  exports** — so nothing is owed until the app has actually shipped. What is
  needed *before* release is App Store Connect's export questionnaire, plus a
  French declaration only if France is a market. See
  [Privacy manifest and export compliance](#privacy-manifest-and-export-compliance).
- ~~The **paid Apple Developer Program enrolment** is the remaining *engineering*
  gate.~~ Resolved: the enrolment is paid, the device is registered, and a
  signed `.ipa` has shipped to TestFlight.
- ~~**Reviewer sign-in credentials block external testing.**~~ Resolved: the
  email and code are known, proven against production 2026-09-03, and present
  in both ASC review records (verified 2026-09-04). What gates a submission now
  is metadata and the export-compliance answer, not access.
- ⬜ **Export compliance is recorded wrongly in App Store Connect.** Both builds
  read `usesNonExemptEncryption: false`, which claims our encryption is exempt;
  it is not. Fixing it needs no rebuild. See
  [`EXPORT-COMPLIANCE.md`](EXPORT-COMPLIANCE.md).
