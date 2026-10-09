# blocwise

<picture>
  <source media="(prefers-reduced-motion: reduce)" srcset="docs/media/banner.png">
  <img src="docs/media/blocwise.gif" alt="blocwise: presentation, domain and data layers, the action states and the eight skills">
</picture>

Engineering skills for AI coding agents working on Flutter apps built with `flutter_bloc`.

Each skill is a short, opinionated playbook: the rules, the reason behind each rule, the mistakes that keep happening in real apps, and copy-ready Dart that compiles.
The lessons come from shipping and maintaining a production payments app, so the pack is strict wherever money, retries and user trust are involved.

## Skills

| Skill | Reach for it when |
| --- | --- |
| `bloc-feature-architecture` | Starting a feature, deciding which layer a file belongs to, or reviewing imports. Ships `new_feature.sh` (stubs a whole feature) and `check_layers.sh` (a grep-only layer checker for CI). |
| `bloc-failures-and-results` | Writing repositories, API calls or anything that can fail. A sealed `AppFailure` set, a dependency-free `Result`, one guarded catch point, and the outcome-unknown rule for mutations. |
| `bloc-sdk-ports` | Touching analytics, crash reporting, URL launching, sharing, storage or any vendor SDK. Ports, adapters, no-op and recording fakes, privacy redaction. |
| `bloc-state-management` | Writing a Cubit or Bloc: state shape, emitting after `await`, stale responses, timers, provider scope, `buildWhen` and the stale-snapshot trap. |
| `bloc-ui-effects` | Navigation, snackbars, dialogs or analytics that react to state. One effects listener per feature and one `ActionCubit` per user action. |
| `bloc-testing` | Cubit, repository, widget, effect and golden tests with `bloc_test` and `mocktail`, regression-first bug fixes. |
| `bloc-leak-guard` | Hunting or preventing leaks from subscriptions, timers, controllers and listeners. Ships `leak_audit.sh`. |
| `bloc-feature-flags` | Adding, reading or retiring a feature flag, kill switch or experiment, independent of the flag vendor. |

The skills refer to each other and share one set of core types, so install the whole pack.

## The rules worth remembering

- Presentation never imports data. Data and presentation both depend on the domain.
- Exceptions never cross a layer. Data code returns `Result`, and there is exactly one `try/catch` per call, in `RequestGuard`.
- After a write, a timeout, a dropped connection or a 5xx means **the outcome is unknown**. Do not retry it. Read the server state to find out what happened. Only a 4xx is a refusal, and a status you do not recognise is never shown as success.
- A cubit owns the flow and never touches `BuildContext`. Side effects live in listeners, not in `build` and not after an `await` in `onPressed`.
- Every vendor SDK sits behind a port the app owns, so tests never hit a platform channel.
- Every flag has a safe default in code. Kill switches are turned off by rollout, never by deleting the flag.

## Stack

| Concern | Assumed |
| --- | --- |
| State | `flutter_bloc` / `bloc` 9 (Cubit by default, Bloc when you need event transformers) |
| DI | `get_it` (`injectable` works too) |
| Errors | The pack's own `Result` and sealed `AppFailure` (no `dartz` or `fpdart` needed; an app already on `Either` keeps it, see `bloc-failures-and-results`) |
| HTTP | `dio`, behind an app-owned `ApiClient` |
| Tests | `bloc_test`, `mocktail`, `fake_async` |

## Install

### Claude Code

```text
/plugin marketplace add raymondddenny/blocwise
/plugin install blocwise@blocwise
```

### Any agent that reads skill folders

```bash
npx skills add raymondddenny/blocwise
```

Or copy the folders under `skills/` into your agent's skills directory (for Claude Code: `~/.claude/skills/` or `.claude/skills/` in your project).

## Use it

Skills load on their own when the task matches their description.
You can also ask for one directly, for example "use bloc-failures-and-results to review this repository".

To start a feature:

```bash
bash ~/.claude/skills/bloc-feature-architecture/scripts/new_feature.sh invoices --entity Invoice
bash ~/.claude/skills/bloc-feature-architecture/scripts/check_layers.sh
```

The scaffold expects the core files from `bloc-failures-and-results/assets` and `bloc-state-management/assets` to be in `lib/core/`.
Each asset starts with a `// Target:` comment saying where it goes.

## Enforce it in CI

```yaml
- run: bash path/to/check_layers.sh lib/features
- run: bash path/to/leak_audit.sh lib --strict
```

Both are plain bash and grep, so they need no Dart toolchain.

## Repository checks

- `tests/validate.sh`: frontmatter, names, script syntax and a secret scan.
- `tests/compile_assets.sh`: copies every Dart asset into a fresh Flutter project, then runs `dart format`, `flutter analyze --fatal-infos` and the example tests.

Both run in GitHub Actions on every push.

## License

MIT
