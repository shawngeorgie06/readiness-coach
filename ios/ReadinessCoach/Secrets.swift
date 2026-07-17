import Foundation

/// Local, single-user secrets. This file is committed with an EMPTY token; the
/// real value is set only on this machine and kept out of git via
/// `git update-index --skip-worktree ios/ReadinessCoach/Secrets.swift`, so the
/// public repo never contains the backend bearer token.
///
/// To pre-fill onboarding on a fresh install, paste your API token below on the
/// local machine only. Leaving it empty just means you type the token once.
enum Secrets {
    /// Default API bearer token used to pre-fill onboarding. Empty in the repo.
    static let defaultAPIToken = ""
}
