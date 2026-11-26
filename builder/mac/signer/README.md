# cartouche-signer

The helper Cartouche for Mac carries in `Contents/Helpers`. It renews Cartouche on the player's iPhone from the Mac the iPhone is plugged in to, as SideStore renews it on the iPhone: a new provisioning profile for Cartouche's App ID, made by Apple for this iPhone and the account's certificates, then installed by the iPhone's `misagent` ([decision 165](../../../docs/decisions/165.md)). Nothing is signed or installed again. Cartouche keeps its games, its saves and its Increased Memory Limit, and no App ID is taken while Cartouche's still exists. The app runs one command at a time, and the helper reads and writes one JSON object per line ([`Signer.swift`](../Sources/BuilderKit/Signer.swift)). The app's **iPhone** page signs in with it and shows what it found, and the app renews with it every half hour when Cartouche is due ([`Renewals.swift`](../Sources/CartoucheBuilder/Renewals.swift)). When a profile no longer opens Cartouche, because the certificate it was signed with is gone, the helper installs the newest Cartouche over it instead, signed for the same team, which keeps its games and saves too (`reinstall`, below).

It signs in to Apple the way the Cartouche Installer does ([`installer/src-tauri`](../../../installer/src-tauri)), with [isideload](https://crates.io/crates/isideload) and [idevice](https://crates.io/crates/idevice), from the crates of the Installer's `Cargo.lock`. It is tested against the Installer's fakes.

## What it keeps, and where

- **The session, never the password.** A sign-in sends the password and the two-factor code to Apple, and nothing else. The helper then keeps Apple's tokens in `session.json`: the Xcode token for the developer services, and the session it came from, which gives a new Xcode token without the password once the old one ends. Once Apple ends that session (a new sign-in elsewhere, a password change, or the days Apple gives it), only the password signs in again (`session-ended`).
- **Its folder.** `~/Library/Application Support/Cartouche Builder/Signer`, the app's `BuilderHome.signer`, holds `session.json` (`0600`), the app's `renewals.log` (`0600`) and isideload's files, `isideload/`, with the anisette machine Apple knows this Mac by and, once it has installed Cartouche, the private key of its certificate, *Cartouche for Mac* (`0700`). `Downloads/` (`0700`) holds Cartouche's IPA while it is installed, and nothing after. It never uses the keychain: the app is signed ad hoc, so macOS would ask for it again after each update.
- **On the iPhone.** The new profile, beside the ones it already holds, and the renewal's date in Cartouche's Documents, `.cartouche/renewal.json`, with the same fields as SideStore's record of an app: `bundleIdentifier`, `expirationDate`, `refreshedDate`, and `by: "mac"`. Cartouche shows its expiry from its embedded profile, which a renewal does not change, and from SideStore's record ([`CartoucheSignature`](../../../launcher/Sources/CartoucheDevice.swift)). Reading this file too is for the next change.

## When it renews, and what it checks

`renew --if-due` renews only in Cartouche's last two days, or once it has expired ([`rules.rs`](src/rules.rs)). Before that, it reaches neither Apple nor anything beyond the iPhone's list of apps and profiles. Without `--if-due`, it renews when asked. A normal renewal sends Apple three requests: `listTeams`, `listAppIds` and `downloadTeamProvisioningProfile`.

The profile is installed only if it would open Cartouche. It has to be for Cartouche's App ID and this iPhone, list a certificate of the profile Cartouche runs under now, and grant every entitlement that profile grants. If the App ID is gone, it is registered again (`registeredAppId`, one of the ten a week) with the app group and Increased Memory Limit the Installer gives it. If the iPhone is missing from the profile, the iPhone is registered. If the certificate Cartouche was signed with is no longer on the account (revoked elsewhere), the helper installs nothing and says `certificate-gone`: only an install over Cartouche opens it again. The helper never revokes a certificate. Cartouche installed with another Apple Account is left alone (`other-team`).

## Installing over Cartouche

`reinstall` installs the newest Cartouche over the copy on the iPhone, as the Cartouche Installer updates it ([`reinstall.rs`](src/reinstall.rs)). It is for the one case a profile does not mend, `certificate-gone`. The app runs it by itself once Cartouche has expired that way, and when the player asks on the **iPhone** page before that.

- **The newest release, from GitHub alone.** The release with the highest version in the source Cartouche's built-in SideStore updates from (`CARTOUCHE_SIDESTORE_SOURCE_URL`), downloaded only from the repository's releases on GitHub and checked against the source's size and SHA-256 ([`release.rs`](src/release.rs)). Anything else is `download`, and nothing is installed.
- **The same team, the same identifier.** Only the copy of the session's team, signed for that team with a certificate of this Mac, *Cartouche for Mac*, made the first time. The identifier stays the copy's, so iOS installs over it and keeps its container: the games, the saves, Increased Memory Limit on its App ID, and SideStore's pairing file. The certificate goes into Cartouche's SideStore framework too, as the Installer puts it, for Cartouche to renew itself with.
- **Never a certificate revoked.** When the account already has as many certificates as Apple allows, the helper installs nothing and says `no-certificate-left`. The player frees one in the Installer's **Certificates** page, or on the other computer that holds it.
- **What is left.** The IPA and what isideload unpacked of it in the temporary folder are removed, whatever the outcome. The helper then reads the iPhone again, and answers only if Cartouche runs until later than before.

It reaches the iPhone through usbmuxd, as the Finder does: by the cable, or on the same Wi-Fi once Wi-Fi sync is on. It does not work through Tailscale, because usbmuxd finds an iPhone on the network by Bonjour. LocalDevVPN plays no part.

## Commands

```
cartouche-signer [--folder DIR] [--anisette URL] devices
cartouche-signer [--folder DIR] session
cartouche-signer [--folder DIR] [--anisette URL] sign-in --email EMAIL
cartouche-signer [--folder DIR] sign-out
cartouche-signer [--folder DIR] [--anisette URL] renew --udid UDID [--if-due]
cartouche-signer [--folder DIR] [--anisette URL] reinstall --udid UDID
cartouche-signer version
```

Each command writes its events as they come, then its answer as the last line, `{"result": …}`, or what stopped it, `{"error": {"kind": …, "stage": …, "code": …, "message": …}}`. It exits with 0 for an answer, 1 for an error, and 2 for a command it does not take.

- `devices`: `{"iphones": [{"udid", "name", "ios", "link": "usb" | "network", "cartouche": [{"bundleId", "version", "teamId", "expires", "due": "not-yet" | "now" | "expired", "from"}], "error"}]}`.
- `session`, `sign-out`: `{"signedIn", "email", "teamId", "teamName", "since", "refreshed"}`. Never a token.
- `sign-in`: writes `{"event": "password"}` and reads `{"password": …}` on its input. When Apple asks for a code, it writes `{"event": "code", "bySms", "lastError", "numbers", "selectedNumber"}` and reads `{"code": …}`, `{"sms": <number's id>}`, `{"devices": true}`, `{"resend": true}` or `{"cancel": true}`. It waits five minutes for each.
- `renew`: `{"renewed", "bundleId", "before", "expires", "due", "from", "registeredAppId", "refreshedSession", "recorded", "link", "seconds"}`.
- `reinstall`: writes `{"event": "progress", "step": "download" | "sign" | "install", "fraction"}` as it goes, at most once a hundredth of each step, then `{"reinstalled", "bundleId", "version", "previousVersion", "before", "expires", "due", "from", "refreshedSession", "link", "seconds"}`.

The kinds of error are `no-session`, `session-ended`, `wrong-password`, `wrong-code`, `cancelled`, `account-refused`, `too-many-requests`, `anisette`, `apple`, `network`, `no-iphone`, `iphone-refused`, `no-cartouche`, `other-team`, `certificate-gone`, `no-app-ids`, `no-certificate-left`, `download`, `profile-refused`, `iphone`, `usage` and `internal` ([`error.rs`](src/error.rs)). The stages are `session`, `apple`, `download` and `iphone`. The message can name the account or the iPhone, so the app keeps it only in `renewals.log` in this folder (`0600`, its last 200 lines), and never shows it nor puts it in the measurements: the page says each kind in the player's words ([`SignerWords.swift`](../Sources/BuilderKit/SignerWords.swift)).

Dates are RFC 3339, in UTC, to the second. `CARTOUCHE_SIGNER_LOG=debug` makes the error output say more.

## Building and testing

```
cargo test --locked --manifest-path builder/mac/signer/Cargo.toml          # about 15 s
CARTOUCHE_TEST_LOG=1 cargo test --manifest-path builder/mac/signer/Cargo.toml <name>
cargo build --release --locked --manifest-path builder/mac/signer/Cargo.toml --target aarch64-apple-darwin
```

[`bundle.sh`](../bundle.sh) builds the helper and puts it in the app, or puts in the one `CARTOUCHE_SIGNER_BINARY` names. The **Builder** workflow runs its tests on Linux (job *Signer*), builds it on a Mac of its own (job *Signer for the Mac*), and the app's job puts that one in the app: a build of it in the app's job made that job 7 minutes longer, and its window's checks failed twice.

The tests ([`tests/signer`](tests/signer)) run against the Installer's fakes ([`installer/src-tauri/tests/README.md`](../../../installer/src-tauri/tests/README.md)): an iPhone 17 Pro behind usbmuxd, whose `misagent` keeps the profiles it is given and opens an app only while one of them covers it (`FakeIphone::runs_until`); Apple, which can end a session's Xcode tokens or the whole session; the anisette server; and GitHub, with Cartouche's source and releases. Cartouche is put on the iPhone the way the Installer puts it, with isideload. The tests check that a renewal installs nothing again, keeps the app's files and saves, and asks Apple for no certificate and no App ID. They also check that the password is in no file and no line the helper writes, and they cover each refusal above. An install over Cartouche is checked to keep its saves, to sign it for the same team with this Mac's certificate in SideStore's framework, to revoke nothing when the account is full, and to install nothing that is not the IPA the source lists. A debug build takes `CARTOUCHE_SIGNER_TEST_APPLE_PROXY`, the fake Apple's address, and `CARTOUCHE_SIGNER_TEST_GITHUB_PROXY` with `CARTOUCHE_SIGNER_TEST_GITHUB_CA`, the fake GitHub's. A release build, which the app carries, reads none of them.

None of this has been tried on a real iPhone or a real Mac yet.
