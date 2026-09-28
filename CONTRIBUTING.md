# Contributing

**English** | [简体中文](CONTRIBUTING.zh-CN.md)

## Set up for development

You need macOS 13 or later and Apple Command Line Tools.

```bash
swift build
bash Scripts/run_tests.sh
```

With a full Xcode installation, the test script runs the standard SwiftPM XCTest target. If only Command Line Tools are installed and XCTest is unavailable, it runs the same core cases through a compatible runner.

Create feature branches from the latest upstream `main`. Do not commit task handoffs, chat transcripts, personal plans, or temporary screenshots. Maintain the README, architecture notes, test plans, and build or release documentation alongside the code when relevant.

## Localization

Keep interface text in both `Sources/cpsmart/Resources/en.lproj/Localizable.strings` and `Sources/cpsmart/Resources/zh-Hans.lproj/Localizable.strings`. Use `L10n.tr` for fixed text and `L10n.format` for text with `{0}`, `{1}`, and other arguments. Preserve the same placeholders in both translations. Accessibility permission descriptions live in `Resources/en.lproj/InfoPlist.strings` and `Resources/zh-Hans.lproj/InfoPlist.strings`. Update the English and Chinese documentation together when behavior changes.

## Open a pull request from a fork

1. Fork `dongdaoguang/cpsmart` on GitHub.
2. Set the official repository as `upstream` and your fork as `origin`.
3. Create a branch from `upstream/main` and commit your changes.
4. Push to your fork, then open a pull request against `dongdaoguang/cpsmart:main`.

```bash
git remote rename origin upstream
git remote add origin https://github.com/<your-username>/cpsmart.git
git fetch upstream
git switch -c feature/<feature-name> upstream/main

# After making, testing, and committing your changes
git push -u origin feature/<feature-name>
gh pr create --repo dongdaoguang/cpsmart --base main --head <your-username>:feature/<feature-name>
```

Before submitting a pull request, check that:

- `swift build` and `bash Scripts/run_tests.sh` pass.
- For UI or input changes, complete the relevant checks in the [multi-display and input testing checklist](docs/MULTI_DISPLAY_TESTING.md).
- The pull request contains only product code, tests, and maintained documentation, with no process notes.
- The README, [changelog](CHANGELOG.md), and version numbers match the behavior.
- You have not committed `build/`, `dist/`, `.build/`, local certificates, or notarization credentials.
