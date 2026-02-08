# Contributing to TrustedTime

First off, thank you for considering contributing to **TrustedTime**! It's people like you who make this project a reliable foundation for the Flutter community.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct (Contributor Covenant).

## How Can I Contribute?

### Reporting Bugs
- Use the **GitHub Issue Tracker**.
- Check if the issue has already been reported.
- Provide a clear description and a minimal reproduction case (Dart/Flutter version included).

### Suggesting Enhancements
- Open an issue titled `[Feature Request] ...`.
- Describe the use case and why this enhancement is important for high-integrity timekeeping.

### Pull Requests
1. **Fork the repo** and create your branch from `main`.
2. Ensure you follow the **Senior Lead** coding style (strict types, comprehensive triple-slash comments).
3. Add or update tests. We aim for 90%+ coverage on core engine logic.
4. Run `flutter analyze` and `flutter test` before submitting.
5. All PRs require at least one maintainer approval.

## Development Setup

1. Clone your fork.
2. Run `flutter pub get`.
3. Open the project in VS Code or Android Studio.
4. Use the `example` project to verify changes across platforms.

## Coding Standards

- **Consistency**: Follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style).
- **Documentation**: All public members MUST have descriptive, narrative doc comments.
- **Performance**: Avoid unnecessary object allocations in the critical `now()` path.
