# cartouche-signer

The helper Cartouche for Mac carries in `Contents/Helpers`. It renews Cartouche on the player's iPhone from the Mac the iPhone is plugged in to, as SideStore renews it on the iPhone: a new provisioning profile for Cartouche's App ID, made by Apple for this iPhone and the account's certificates, then installed by the iPhone's `misagent` ([decision 165](../../../docs/decisions/165.md)). Nothing is signed or installed again. Cartouche keeps its games, its saves and its Increased Memory Limit, and no App ID is taken while Cartouche's still exists. The app runs one command at a time, and the helper reads and writes one JSON object per line ([`Signer.swift`](../Sources/BuilderKit/Signer.swift)).

It signs in to Apple the way the Cartouche Installer does ([`installer/src-tauri`](../../../installer/src-tauri)), with [isideload](https://crates.io/crates/isideload) and [idevice](https://crates.io/crates/idevice), from the crates of the Installer's `Cargo.lock`. It is tested against the Installer's fakes.

## What it keeps, and where

- **The session, never the password.** A sign-in sends the password and the two-factor code to Apple, and nothing else. The helper then keeps Apple's tokens in `session.json`: the Xcode token for the developer services, and the session it came from, which gives a new Xcode token without the password once the old one ends. Once Apple ends that session (a new sign-in elsewhere, a password change, or the days Apple gives it), only the password signs in again (`session-ended`).
- **Its folder.** `~/Library/Application Support/Cartouche Builder/Signer`, the app's `BuilderHome.signer`, holds `session.json` (`0600`) and isideload's files, `isideload/`, with the anisette machine Apple knows this Mac by (`0700`). It never uses the keychain: the app is signed ad hoc, so macOS would ask for it again after each update.
- **On the iPhone.** The new profile, beside the ones it already holds, and the renewal's date in Cartouche's Documents, `.cartouche/renewal.json`, with the same fields as SideStore's record of an app: `bundleIdentifier`, `expirationDate`, `refreshedDate`, and `by: "mac"`. Cartouche shows its expiry from its embedded profile, which a renewal does not change, and from SideStore's record ([`CartoucheSignature`](../../../launcher/Sources/CartoucheDevice.swift)). Reading this file too is for the next change.

## When it renews, and what it checks

`renew --if-due` renews only in Cartouche's last two days, or once it has expired ([`rules.rs`](src/rules.rs)). Before that, it reaches neither Apple nor anything beyond the iPhone's list of apps and profiles. Without `--if-due`, it renews when asked. A normal renewal sends Apple three requests: `listTeams`, `listAppIds` and `downloadTeamProvisioningProfile`.

The profile is installed only if it would open Cartouche. It has to be for Cartouche's App ID and this iPhone, list a certificate of the profile Cartouche runs under now, and grant every entitlement that profile grants. If the App ID is gone, it is registered again (`registeredAppId`, one of the ten a week) with the app group and Increased Memory Limit the Installer gives it. If the iPhone is missing from the profile, the iPhone is registered. If the certificate Cartouche was signed with is no longer on the account (revoked elsewhere), the helper installs nothing and says `certificate-gone`: only an install over Cartouche opens it again. The helper never revokes a certificate. Cartouche installed with another Apple Account is left alone (`other-team`).

It reaches the iPhone through usbmuxd, as the Finder does: by the cable, or on the same Wi-Fi once Wi-Fi sync is on. It does not work through Tailscale, because usbmuxd finds an iPhone on the network by Bonjour. LocalDevVPN plays no part.

## Commands

```
cartouche-signer [--folder DIR] [--anisette URL] devices
cartouche-signer [--folder DIR] session
cartouche-signer [--folder DIR] [--anisette URL] sign-in --email EMAIL
cartouche-signer [--folder DIR] sign-out
cartouche-signer [--folder DIR] [--anisette URL] renew --udid UDID [--if-due]
cartouche-signer version
```

Each command writes its events as they come, then its answer as the last line, `{"result": …}`, or what stopped it, `{"error": {"kind": …, "stage": …, "code": …, "message": …}}`. It exits with 0 for an answer, 1 for an error, and 2 for a command it does not take.

- `devices`: `{"iphones": [{"udid", "name", "ios", "link": "usb" | "network", "cartouche": [{"bundleId", "version", "teamId", "expires", "due": "not-yet" | "now" | "expired", "from"}], "error"}]}`.
- `session`, `sign-out`: `{"signedIn", "email", "teamId", "teamName", "since", "refreshed"}`. Never a token.
- `sign-in`: writes `{"event": "password"}` and reads `{"password": …}` on its input. When Apple asks for a code, it writes `{"event": "code", "bySms", "lastError", "numbers", "selectedNumber"}` and reads `{"code": …}`, `{"sms": <number's id>}`, `{"devices": true}`, `{"resend": true}` or `{"cancel": true}`. It waits five minutes for each.
- `renew`: `{"renewed", "bundleId", "before", "expires", "due", "from", "registeredAppId", "refreshedSession", "recorded", "link", "seconds"}`.

The kinds of error are `no-session`, `session-ended`, `wrong-password`, `wrong-code`, `cancelled`, `account-refused`, `too-many-requests`, `anisette`, `apple`, `network`, `no-iphone`, `iphone-refused`, `no-cartouche`, `other-team`, `certificate-gone`, `no-app-ids`, `profile-refused`, `iphone`, `usage` and `internal` ([`error.rs`](src/error.rs)). The stages are `session`, `apple` and `iphone`. The message can name the account or the iPhone, so the app keeps it for its log and for a report the player copies, and never puts it in the measurements.

Dates are RFC 3339, in UTC, to the second. `CARTOUCHE_SIGNER_LOG=debug` makes the error output say more.

## Building and testing

```
cargo test --locked --manifest-path builder/mac/signer/Cargo.toml          # about 10 s
CARTOUCHE_TEST_LOG=1 cargo test --manifest-path builder/mac/signer/Cargo.toml <name>
cargo build --release --locked --manifest-path builder/mac/signer/Cargo.toml --target aarch64-apple-darwin
```

[`bundle.sh`](../bundle.sh) builds the helper and puts it in the app. The **Builder** workflow runs its tests on Linux (job *Signer*), then builds it into the app on the Mac.

The tests ([`tests/signer`](tests/signer)) run against the Installer's fakes ([`installer/src-tauri/tests/README.md`](../../../installer/src-tauri/tests/README.md)): an iPhone 17 Pro behind usbmuxd, whose `misagent` keeps the profiles it is given and opens an app only while one of them covers it (`FakeIphone::runs_until`); Apple, which can end a session's Xcode tokens or the whole session; and the anisette server. Cartouche is put on the iPhone the way the Installer puts it, with isideload. The tests check that a renewal installs nothing again, keeps the app's files and saves, and asks Apple for no certificate and no App ID. They also check that the password is in no file and no line the helper writes, and they cover each refusal above. A debug build takes `CARTOUCHE_SIGNER_TEST_APPLE_PROXY`, the fake Apple's address. A release build, which the app carries, does not read it.

None of this has been tried on a real iPhone or a real Mac yet.
