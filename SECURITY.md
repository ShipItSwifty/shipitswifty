# Security Policy

## Supported Versions

ShipItSwifty is in active development. Security fixes are applied to the
current `main` branch and the most recently tagged release.

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |
| latest tag | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

Please report security vulnerabilities **privately** so they can be addressed
before public disclosure.

- Open a [GitHub private security advisory][gh-advisory] on this repository, or
- Email the maintainer listed in the repository profile (subject prefix
  `[security]`).

Please do **not** open a public GitHub issue for security problems.

When reporting, include:

- A description of the issue and its impact
- Steps to reproduce, or a minimal proof-of-concept
- The affected version, commit, or release tag
- Any suggested mitigation, if you have one

We will acknowledge your report within a few business days and keep you updated
as we triage and fix the issue.

## Threat Model and Secrets Handling

For details on how ShipItSwifty handles credentials (App Store Connect API
keys, Google Play service accounts, code-signing certificates, etc.), see
[`docs/security.md`](docs/security.md).

[gh-advisory]: https://github.com/maniramezan/ShipItSwifty/security/advisories/new
