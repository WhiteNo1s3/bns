# Versioning — the alpha law

Owner, 2026-08-18: "we neglect the versioning, it's +0.01 and an `a`
at the end as this is considered ALPHA."

## The scheme

| Form | Where | Example |
|---|---|---|
| **`0.XXa`** — the human version | in-app (menu footer, about), `.bns` export stamps, dist filenames, what testers report | `0.12a` |
| `0.XX.0+N` — the machine version | `pubspec.yaml` only (semver for the tools; `+N` = Android versionCode) | `0.12.0+4` |

- **+0.01 per shipped wave**: `0.12a → 0.13a → …` (pubspec minor +1 in step).
- **`+N` climbs on every shipped build**, never resets.
- **The `a` falls only at 1.0** — the build where the level-1 day runs
  clean end to end and distribution signing is done. No `b`/beta stage
  is planned unless the owner declares one.

## One source, held by a test

The human version lives in exactly one place:
[`lib/core/version.dart`](../lib/core/version.dart) → `kBnsVersion`.
Everything else reads it — the menu footer, the desktop about dialog,
both exporter stamps. `scripts/build-apple.sh` derives the same form
from pubspec for dist names.

`test/version_law_test.dart` fails the suite whenever `kBnsVersion`
and `pubspec.yaml` drift apart — bumping a wave means touching both,
or the tree goes red. The neglect cannot quietly return.

## Bumping a wave (the whole ritual)

1. `pubspec.yaml`: `0.12.0+4` → `0.13.0+5`
2. `lib/core/version.dart`: `'0.12a'` → `'0.13a'`
3. Ship: dist files come out as `BNS-…-v0.13a.*` by themselves.
