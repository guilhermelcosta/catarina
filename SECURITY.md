# Security policy

## Reporting a vulnerability

Do not open a public issue for a security problem.

Use GitHub Security Advisories on this repository:

<https://github.com/guilhermelcosta/catarina/security/advisories/new>

Include the affected version, the steps to reproduce, and the impact. If the
report includes a secret, rotate it before sending.

## Secret handling

Catarina stores secrets in the system keyring (Secret Service/KWallet) through
QtKeychain. When no keyring is available it falls back to a `0600` file under the
application data directory. Collections only store a `secretId`, never the value.

Never commit real tokens, cookies, passwords, or collection data. The CI secret
scan is a safety net, not a replacement for care.

## Supported versions

Security fixes go to the latest release on `master`. Older tags are not maintained.
