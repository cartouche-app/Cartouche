//! cartouche-signer, which Cartouche for Mac runs out of sight
//! (Contents/Helpers): one command a run, its answer the last line of its
//! output (protocol.rs, README.md).
//!
//!     cartouche-signer [--folder DIR] [--anisette URL] devices
//!     cartouche-signer [--folder DIR] session
//!     cartouche-signer [--folder DIR] [--anisette URL] sign-in --email EMAIL   (input: {"password": …}, then codes)
//!     cartouche-signer [--folder DIR] sign-out
//!     cartouche-signer [--folder DIR] [--anisette URL] renew --udid UDID [--if-due]
//!     cartouche-signer version

use std::{path::PathBuf, process::ExitCode, sync::Arc, time::Duration};

use cartouche_signer::{
    Environment, Failure, Kind, Result, Stage, iphone,
    protocol::{self, event},
    renew::{self, Options},
    session::{self, CodeAsker},
};
use futures::FutureExt;
use isideload::auth::apple_account::{TwoFactorCallbackParams, TwoFactorCallbackResponse};
use serde_json::{Value, json};
use tokio::{
    io::{AsyncBufReadExt, BufReader, Lines, Stdin},
    sync::Mutex,
};

/// How long the signer waits for what the player types: the password, then
/// each code.
const PASSWORD_WAIT: Duration = Duration::from_secs(5 * 60);
const CODE_WAIT: Duration = Duration::from_secs(5 * 60);

#[derive(Default)]
struct Args {
    command: Option<String>,
    folder: Option<PathBuf>,
    anisette: Option<String>,
    email: Option<String>,
    udid: Option<String>,
    if_due: bool,
}

fn usage(message: impl Into<String>) -> Failure {
    Failure::new(Kind::Usage, Stage::Session, message)
}

fn parse(mut words: impl Iterator<Item = String>) -> Result<Args> {
    let mut args = Args::default();
    while let Some(word) = words.next() {
        let mut value = |name: &str| words.next().ok_or_else(|| usage(format!("{name} takes a value")));
        match word.as_str() {
            "--folder" => args.folder = Some(PathBuf::from(value("--folder")?)),
            "--anisette" => args.anisette = Some(value("--anisette")?),
            "--email" => args.email = Some(value("--email")?),
            "--udid" => args.udid = Some(value("--udid")?),
            "--if-due" => args.if_due = true,
            flag if flag.starts_with("--") => return Err(usage(format!("Unknown option {flag}"))),
            command if args.command.is_none() => args.command = Some(command.to_string()),
            extra => return Err(usage(format!("Unexpected {extra}"))),
        }
    }
    Ok(args)
}

/// The signer's folder, by default the Builder's own folder's Signer, as
/// the app passes it (BuilderHome).
fn default_folder() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    home.join("Library/Application Support/Cartouche Builder/Signer")
}

fn environment(args: &Args) -> Result<Environment> {
    let folder = args.folder.clone().unwrap_or_else(default_folder);
    #[allow(unused_mut)]
    let mut env = Environment::system(folder, args.anisette.clone())?;
    // The tests' fake Apple: never in the signer the app carries, built
    // for release.
    #[cfg(debug_assertions)]
    if let Some(proxy) = std::env::var("CARTOUCHE_SIGNER_TEST_APPLE_PROXY").ok().filter(|p| !p.is_empty()) {
        env.apple_proxy = Some(proxy);
    }
    Ok(env)
}

type Input = Arc<Mutex<Lines<BufReader<Stdin>>>>;

/// The next line the app sends, as JSON; None once it closed the input or
/// after WAIT.
async fn next_input(input: &Input, wait: Duration) -> Option<Value> {
    let mut lines = input.lock().await;
    loop {
        match tokio::time::timeout(wait, lines.next_line()).await {
            Ok(Ok(Some(line))) if line.trim().is_empty() => continue,
            Ok(Ok(Some(line))) => return serde_json::from_str(&line).ok(),
            _ => return None,
        }
    }
}

/// Asks the app for a code: an event, then its answer on the input.
fn code_asker(input: Input) -> CodeAsker {
    Arc::new(move |params: TwoFactorCallbackParams| {
        let input = input.clone();
        async move {
            let numbers: Vec<Value> = params
                .numbers
                .iter()
                .map(|n| json!({ "id": n.id, "number": n.number_with_dial_code, "lastTwoDigits": n.last_two_digits }))
                .collect();
            event(
                "code",
                json!({ "bySms": params.sms, "lastError": params.last_error, "numbers": numbers, "selectedNumber": params.selected_number_id }),
            );
            let answer = next_input(&input, CODE_WAIT).await.unwrap_or(Value::Null);
            let text = |key: &str| answer.get(key).and_then(|v| v.as_str()).map(str::trim).filter(|c| !c.is_empty());
            Ok(if let Some(code) = text("code") {
                TwoFactorCallbackResponse::SubmitCode(code.to_string())
            } else if let Some(id) = answer.get("sms").and_then(|v| v.as_u64()) {
                TwoFactorCallbackResponse::SendSms(id as u32)
            } else if answer.get("devices").and_then(|v| v.as_bool()) == Some(true) {
                TwoFactorCallbackResponse::SendToDevices
            } else if answer.get("resend").and_then(|v| v.as_bool()) == Some(true) {
                TwoFactorCallbackResponse::ResendCode
            } else {
                TwoFactorCallbackResponse::Abort
            })
        }
        .boxed()
    })
}

fn value(answer: Result<impl serde::Serialize>) -> Result<Value> {
    answer.and_then(|v| serde_json::to_value(v).map_err(|e| usage(e.to_string())))
}

async fn run(args: Args) -> Result<Value> {
    let command = args
        .command
        .clone()
        .ok_or_else(|| usage("No command: devices, session, sign-in, sign-out, renew or version"))?;
    if command == "version" {
        return Ok(json!({ "version": env!("CARGO_PKG_VERSION") }));
    }
    let env = environment(&args)?;
    match command.as_str() {
        "devices" => Ok(json!({ "iphones": iphone::list(&env).await? })),
        "session" => value(session::info(&env)),
        "sign-in" => {
            let email = args.email.clone().ok_or_else(|| usage("sign-in takes --email"))?;
            let input: Input = Arc::new(Mutex::new(BufReader::new(tokio::io::stdin()).lines()));
            event("password", json!({}));
            let password = next_input(&input, PASSWORD_WAIT)
                .await
                .and_then(|v| v.get("password").and_then(|p| p.as_str()).map(str::to_string))
                .filter(|p| !p.is_empty())
                .ok_or_else(|| Failure::new(Kind::Cancelled, Stage::Session, "No password came"))?;
            let signed_in = session::sign_in(&env, &email, &password, code_asker(input)).await;
            drop(password);
            value(signed_in)
        }
        "sign-out" => {
            session::sign_out(&env)?;
            value(session::info(&env))
        }
        "renew" => {
            let udid = args.udid.clone().ok_or_else(|| usage("renew takes --udid"))?;
            let options = Options { only_if_due: args.if_due, ..Options::default() };
            value(renew::renew(&env, &udid, options).await)
        }
        other => Err(usage(format!("Unknown command {other}"))),
    }
}

fn main() -> ExitCode {
    // What isideload and idevice say, on the error output, which the app
    // keeps with its logs: warnings, or more with CARTOUCHE_SIGNER_LOG.
    let level = std::env::var("CARTOUCHE_SIGNER_LOG")
        .ok()
        .and_then(|l| l.parse::<tracing::Level>().ok())
        .unwrap_or(tracing::Level::WARN);
    let _ = tracing_subscriber::fmt().with_writer(std::io::stderr).with_ansi(false).with_max_level(level).try_init();
    cartouche_signer::init();
    let outcome = parse(std::env::args().skip(1)).and_then(|args| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| Failure::new(Kind::Internal, Stage::Session, e.to_string()))?
            .block_on(run(args))
    });
    match outcome {
        Ok(value) => {
            protocol::result(&value);
            ExitCode::SUCCESS
        }
        Err(failure) => {
            protocol::failure(&failure);
            ExitCode::from(if failure.kind == Kind::Usage { 2 } else { 1 })
        }
    }
}
