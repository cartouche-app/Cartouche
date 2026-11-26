//! What can stop the signer, by kind: the Mac app says what to do from the
//! kind alone (`Signer.swift`), and its measurements count them by kind and
//! stage, never with the message, which can name the account or the iPhone.

use std::fmt;

use idevice::IdeviceError;
use isideload::SideloadError;
use rootcause::Report;
use serde::Serialize;

/// Why the signer stopped.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Kind {
    /// No Apple Account was signed in on this Mac, or it was signed out.
    NoSession,
    /// Apple ended the session: only the password signs in again.
    SessionEnded,
    /// The password Apple refused, at a sign-in.
    WrongPassword,
    /// The two-factor code Apple refused.
    WrongCode,
    /// The player closed the sign-in, or gave no code.
    Cancelled,
    /// The account is locked, or under 18 for the developer services.
    AccountRefused,
    /// Apple asked to wait: too many requests from this Mac.
    TooManyRequests,
    /// The anisette server did not answer, or not as expected.
    Anisette,
    /// Apple's developer services refused, with their code.
    Apple,
    /// Apple or the anisette server could not be reached.
    Network,
    /// The iPhone is not plugged in, nor on the Wi-Fi with its sync on.
    NoIphone,
    /// The iPhone does not trust this Mac, or is locked.
    IphoneRefused,
    /// Cartouche is not on the iPhone.
    NoCartouche,
    /// Cartouche on the iPhone is another Apple Account's.
    OtherTeam,
    /// The certificate Cartouche was signed with is gone from the account:
    /// a new profile would not open it. Only an install over it does.
    CertificateGone,
    /// No App ID left this week to register Cartouche's again.
    NoAppIds,
    /// The iPhone refused the profile.
    ProfileRefused,
    /// The iPhone's connection ended, or it answered what it should not.
    Iphone,
    /// The command was not one the signer takes.
    Usage,
    /// Anything else.
    Internal,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::NoSession => "no-session",
            Kind::SessionEnded => "session-ended",
            Kind::WrongPassword => "wrong-password",
            Kind::WrongCode => "wrong-code",
            Kind::Cancelled => "cancelled",
            Kind::AccountRefused => "account-refused",
            Kind::TooManyRequests => "too-many-requests",
            Kind::Anisette => "anisette",
            Kind::Apple => "apple",
            Kind::Network => "network",
            Kind::NoIphone => "no-iphone",
            Kind::IphoneRefused => "iphone-refused",
            Kind::NoCartouche => "no-cartouche",
            Kind::OtherTeam => "other-team",
            Kind::CertificateGone => "certificate-gone",
            Kind::NoAppIds => "no-app-ids",
            Kind::ProfileRefused => "profile-refused",
            Kind::Iphone => "iphone",
            Kind::Usage => "usage",
            Kind::Internal => "internal",
        }
    }
}

/// Where it stopped, for the measurements: signing in, Apple's developer
/// services, or the iPhone.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Stage {
    Session,
    Apple,
    Iphone,
}

/// A failure, with its kind, its stage and what was said, for the Mac's
/// log and a report the player copies (never sent as it is).
#[derive(Clone, Debug, Serialize)]
pub struct Failure {
    pub kind: Kind,
    pub stage: Stage,
    /// Apple's code, when Apple gave one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<i64>,
    pub message: String,
}

impl Failure {
    pub fn new(kind: Kind, stage: Stage, message: impl Into<String>) -> Self {
        Failure { kind, stage, code: None, message: message.into() }
    }

    pub fn with_code(mut self, code: i64) -> Self {
        self.code = Some(code);
        self
    }

    /// A failure of Apple's services, by what isideload reported. AT_SIGN_IN
    /// tells a wrong password from a session Apple ended: both are -22406.
    pub fn from_apple(report: &Report, stage: Stage, at_sign_in: bool) -> Self {
        let message = report.to_string();
        for cause in report.iter_reports() {
            if let Some(err) = cause.downcast_current_context::<SideloadError>() {
                match err {
                    &SideloadError::AuthWithMessage(code, _) => {
                        let kind = match code {
                            -20209 => Kind::AccountRefused,
                            -22406 | -22421 if at_sign_in => Kind::WrongPassword,
                            -22406 | -22421 => Kind::SessionEnded,
                            -21669 => Kind::WrongCode,
                            _ if at_sign_in => Kind::WrongPassword,
                            _ => Kind::SessionEnded,
                        };
                        return Failure::new(kind, Stage::Session, message).with_code(code);
                    }
                    &SideloadError::DeveloperError(code, _) => {
                        let kind = match code {
                            1100 => Kind::SessionEnded,
                            1102 => Kind::AccountRefused,
                            _ => Kind::Apple,
                        };
                        return Failure::new(kind, stage, message).with_code(code);
                    }
                    SideloadError::IdeviceError(e) => return Failure::from_iphone(e),
                    _ => {}
                }
            }
            if let Some(err) = cause.downcast_current_context::<reqwest::Error>() {
                if err.status().map(|s| s.as_u16()) == Some(429) {
                    return Failure::new(Kind::TooManyRequests, stage, message).with_code(429);
                }
                if err.is_connect() || err.is_timeout() {
                    return Failure::new(Kind::Network, stage, message);
                }
            }
            let text = cause.to_string();
            if text.contains("No 2FA code provided") || text.contains("No 2FA method selected") {
                return Failure::new(Kind::Cancelled, Stage::Session, message);
            }
            if text.contains("429") || text.contains("Too Many Requests") {
                return Failure::new(Kind::TooManyRequests, stage, message).with_code(429);
            }
            if text.contains("Not enough available app IDs") {
                return Failure::new(Kind::NoAppIds, Stage::Apple, message);
            }
            if text.contains("anisette") || text.contains("Anisette") {
                return Failure::new(Kind::Anisette, stage, message);
            }
        }
        Failure::new(Kind::Internal, stage, message)
    }

    /// A failure of the iPhone's services.
    pub fn from_iphone(error: &IdeviceError) -> Self {
        let message = error.to_string();
        let kind = match error {
            IdeviceError::DeviceNotFound => Kind::NoIphone,
            IdeviceError::InvalidHostID
            | IdeviceError::PasswordProtected
            | IdeviceError::PairingDialogResponsePending
            | IdeviceError::UserDeniedPairing
            | IdeviceError::SessionInactive
            | IdeviceError::DeviceLocked => Kind::IphoneRefused,
            IdeviceError::MisagentFailure => Kind::ProfileRefused,
            _ => Kind::Iphone,
        };
        Failure::new(kind, Stage::Iphone, message)
    }
}

impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.kind.as_str(), self.message)
    }
}

impl std::error::Error for Failure {}

pub type Result<T> = std::result::Result<T, Failure>;
