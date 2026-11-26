//! The signer's tests, against the Cartouche Installer's fakes (harness.rs).
//!
//!     cargo test --locked --manifest-path builder/mac/signer/Cargo.toml
//!     CARTOUCHE_TEST_LOG=1 cargo test --manifest-path builder/mac/signer/Cargo.toml <name>

mod cli;
mod harness;
mod reinstall;
mod renew;
mod session;
