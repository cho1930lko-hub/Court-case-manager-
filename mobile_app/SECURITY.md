# Repository security rules

## Never commit
- Real Android signing files: `*.jks`, `*.keystore`, `*.p12`, `*.pfx`
- Real `key.properties` files or signing passwords
- API keys, access tokens, service-role keys, private certificates, or production secrets
- Device databases, backups, or user/case data

## Android release signing
Keep the original signing keystore outside the repository in a secure location. Supply its path and passwords only through a protected local build environment or CI secret store. Do not generate a replacement key as part of routine cleanup.

A sanitized example may contain placeholder values only. It must never contain working credentials.

## Before every commit and archive
Inspect staged/tracked files for credential-like values and signing artifacts. Confirm that no private key or real password is included. If a secret was previously committed, removing it from the latest tree does not erase Git history; rotate/revoke the exposed credential as appropriate.
