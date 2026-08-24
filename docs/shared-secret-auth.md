## Shared-Secret Authentication Updates

This document describes the current TURN REST shared-secret authentication
behavior and the new configuration for controlling accepted digest
algorithms.

## Scope

Shared-secret authentication is enabled with `use-auth-secret` and uses
time-limited usernames (for example `timestamp:userid`) and passwords derived
from the shared secret.

Recent changes add SHA-256 support for this flow and keep compatibility with
existing SHA-1 deployments.

## New Setting: rest-api-sha-algorithms

Use `rest-api-sha-algorithms` to control which HMAC digest algorithms are
accepted when validating TURN REST shared-secret credentials.

- Type: comma-separated list
- Valid values: `sha1`, `sha256`, `sha1,sha256`
- Default when unset: `sha1,sha256`
- Evaluation order: left to right

Examples:

```ini
# legacy compatibility only
rest-api-sha-algorithms=sha1

# SHA-256 only
rest-api-sha-algorithms=sha256

# mixed-mode migration (default behavior)
rest-api-sha-algorithms=sha1,sha256
```

If `rest-api-sha-algorithms` is not present in configuration, coturn does not
fall back to SHA-1-only. It accepts both SHA-1 and SHA-256 by default.

## Operational Effects

- `sha1` only: strict legacy mode.
- `sha256` only: rejects SHA-1-derived REST credentials.
- `sha1,sha256`: accepts either, useful while migrating issuers to SHA-256.

Validation is attempted using each configured digest in order until one
matches, or authentication fails.

## Related Settings

- `use-auth-secret`: enables TURN REST shared-secret auth mode.
- `static-auth-secret`: sets a static shared secret.
- `rest-api-separator`: separator in REST usernames, default `:`.

If `static-auth-secret` is not set, coturn attempts to load secret values from
the user database `turn_secret` table.

## RFC Notes

The SHA-256 update aligns with partial RFC 8489 authentication support in this
area. `USERHASH` and full RFC 8489 parity are not included in this change.
