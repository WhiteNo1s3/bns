/// THE VERSION, IN ONE PLACE (owner, 2026-08-18: "we neglect the
/// versioning, it's +0.01 and an `a` at the end as this is considered
/// ALPHA"). The scheme is law:
///
///   0.XXa  — alpha. XX steps by +0.01 per shipped wave.
///            The letter falls only at 1.0 — the build where the
///            level-1 day runs clean and signing is done.
///
/// pubspec.yaml keeps the machine form `0.XX.0+N` (semver for the
/// tools; `+N` is the Android versionCode, climbing every shipped
/// build). This constant is the HUMAN version — the one the app shows,
/// exports stamp, and dist files wear. A test holds the two together
/// so the neglect cannot quietly return.
const String kBnsVersion = '0.15a';
