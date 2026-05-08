# macOS Bash: `declare -A` Fails with "unbound variable"

## Context

macOS ships with Bash 3.2 (frozen since 2007 due to GPLv3 licensing). Bash 3.2 does
not support associative arrays (`declare -A`). When a script using `declare -A` is
run under the system `bash` with `set -u` (nounset) active, Bash 3.2 misparses the
array key syntax and aborts immediately.

**Error observed:**

```text
bootstrap/init-bootstrap.sh: line 6: container: unbound variable
```

## Prerequisites

- macOS with Homebrew installed
- Terminal access

## Root Cause

```bash
bash --version
# GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
```

macOS `/bin/bash` is 3.2. Associative arrays (`declare -A`) require Bash 4.0+.
With `set -u` active, the failed parse of `["container-runtime"]` causes `container`
to be treated as an unset variable — triggering an immediate abort.

!!! note "Why is macOS Bash stuck at 3.2?"
    Apple has not updated the system `bash` since 2007 because Bash switched to the
    GPLv3 license with version 4.0. Apple only ships GPLv2-licensed software in the
    base OS.

## Fix

### Option 1 — Install Bash 5.x via Homebrew (preferred)

```bash
brew install bash
```

Update the script shebang to pin it to Homebrew bash explicitly:

```bash
#!/opt/homebrew/bin/bash
```

!!! tip "Why not rely on `#!/usr/bin/env bash`?"
    On macOS, `/bin` takes priority over `/opt/homebrew/bin` in the default `PATH`.
    `env bash` resolves to the system 3.2 unless Homebrew is explicitly prepended to
    `PATH`. Pinning the shebang is safer for scripts shared across team machines.

### Option 2 — Rewrite without associative arrays (Bash 3.2 compatible)

Replace `declare -A` with a `case` function. Works on Bash 3.2, 5.x, and `sh`:

```bash
get_title() {
  case "$1" in
    container-runtime)   echo "Container Runtime" ;;
    language-runtimes)   echo "Language Runtimes" ;;
    components)          echo "Components" ;;
  esac
}

title="$(get_title "$folder")"
```

!!! tip "Why `case` instead of `declare -A`?"
    The `case` statement is a POSIX construct supported by all shell versions. It
    avoids any dependency on Bash version and works in scripts invoked with `#!/bin/sh`.

## Verification

```bash
/opt/homebrew/bin/bash --version
```

Expected:

```text
GNU bash, version 5.x.x(1)-release
```

```bash
bash bootstrap/init-bootstrap.sh
```

Expected:

```text
✅  Created: container-runtime/
✅  Created: language-runtimes/
...
🎉 All bootstrap folders initialized successfully.
```

## Troubleshooting

### Script still fails after installing Homebrew bash

**Cause:** `#!/usr/bin/env bash` still resolves to `/bin/bash` (3.2) because `/bin`
precedes `/opt/homebrew/bin` in `PATH`.

**Fix:** Prepend Homebrew to `PATH` in your shell profile:

```bash
export PATH="/opt/homebrew/bin:$PATH"
```

Or use the absolute shebang:

```bash
#!/opt/homebrew/bin/bash
```

Verify which `bash` `env` resolves to:

```bash
which bash
# /opt/homebrew/bin/bash  ← correct
# /bin/bash               ← still pointing to system bash, fix PATH
```

!!! warning
    Never delete or replace `/bin/bash` on macOS. System scripts and macOS internals
    depend on it. Always install a parallel Homebrew version instead.

## Related

- [Bash 4.0 release notes — Associative Arrays](https://tiswww.case.edu/php/chet/bash/CHANGES)
- [Homebrew — brew.sh](https://brew.sh)
- [GNU bash manual — Arrays](https://www.gnu.org/software/bash/manual/bash.html#Arrays)
