# MkDocs Live Reload: Auto-Rebuild on File Change Restored

## Context

The local MkDocs development server (`mkdocs serve`) was not auto-rebuilding when files were
edited. The browser required a manual refresh and the server had to be restarted after every
change. The repository (`ibtisam-iq/runbook`) uses `docs_dir: .` (repository root as the docs
source), enabled by the `same-dir` plugin. This is an atypical setup that introduces a
file-watching loop that standard configurations do not have.

After the initial fix (downgrading `click`), a second issue surfaced: changes to actual content
files (e.g., `workstation/*.md`) were not triggering a rebuild even though `.` was listed in
watched paths. This was caused by `watchdog` using macOS FSEvents, which misses changes in deep
directory trees when the watched root contains hundreds of files including `.venv/` and `.git/`.
Forcing polling mode resolved it completely, and also enabled true browser auto-refresh without
any manual reload.

## What Was Done

| Item | Detail |
|---|---|
| Root cause 1 | `click > 8.2.1` silently broke MkDocs file watching |
| Root cause 2 | macOS FSEvents backend misses changes in large directory trees |
| Secondary cause | `docs_dir: .` with `site_dir: site/` creates an infinite rebuild loop |
| Fix 1 | Downgraded `click` to `8.2.1` |
| Fix 2 | Added `watch:` block to `mkdocs.yml` |
| Fix 3 | Moved `site_dir` to `/tmp/mkdocs-runbook/` to break the loop |
| Fix 4 | Installed `watchdog[watchmedo]` and forced polling mode via env var |
| Dev command | `WATCHDOG_FORCE_POLLING=1 mkdocs serve --livereload --dirtyreload --watch-theme` |

## Prerequisites

- Python virtual environment (`.venv`) with MkDocs Material installed
- `same-dir` plugin installed (required for `docs_dir: .`)
- Repository cloned locally at its root

## Steps

### 1. Diagnose the `click` version

```bash
pip show click
```

If the version is above `8.2.1`, live reload is silently broken. The
`Watching paths for changes:` line will not appear in the server output at all, regardless of
configuration.

### 2. Downgrade `click`

```bash
pip install "click==8.2.1"
```

> **Why this specific version:** A regression introduced in `click > 8.2.1` broke the
> file-watching mechanism MkDocs depends on. MkDocs does not pin this dependency, so a fresh
> `pip install mkdocs-material` pulls the broken version automatically.

### 3. Add `watch:` block to `mkdocs.yml`

```yaml
watch:
  - docs/overrides
  - docs/stylesheets
  - mkdocs.yml
```

> **Why:** MkDocs only watches `docs_dir` by default. The theme override directory
> (`docs/overrides`) and custom CSS (`docs/stylesheets`) sit outside the default watch scope.
> Without this block, changes to templates or stylesheets do not trigger a rebuild.

### 4. Move `site_dir` outside the repository root

```yaml
site_dir: /tmp/mkdocs-runbook/
```

> **Why:** With `docs_dir: .`, MkDocs watches the entire repository root. The default
> `site_dir: site/` is inside that root, so every build writes output into the watched path,
> which triggers another rebuild, creating an infinite loop. Moving `site_dir` to `/tmp/`
> breaks the loop because the output folder is no longer inside the watched directory.

Also add `site/` to `exclude_docs` as a safety net for any machine where `site_dir` still
resolves inside the repo:

```yaml
exclude_docs: |
  README.md
  site/
```

### 5. Install watchdog with watchmedo extras

```bash
pip install "watchdog[watchmedo]"
```

> **Why:** The base `watchdog` install does not always include the polling backend. The
> `watchmedo` extras ensure the full watchdog toolkit is available, including the
> `WATCHDOG_FORCE_POLLING` mode used in the next step.

### 6. Serve with polling mode and all required flags

```bash
WATCHDOG_FORCE_POLLING=1 mkdocs serve --livereload --dirtyreload --watch-theme
```

> **Why `WATCHDOG_FORCE_POLLING=1`:** On macOS, `watchdog` uses FSEvents as its backend by
> default. FSEvents is unreliable on large directory trees - it silently misses file changes
> in subdirectories when the watched root contains thousands of files (`.venv/`, `.git/`,
> all content folders). Forcing polling mode makes `watchdog` check every file on a timer
> instead, which is slightly slower but 100% reliable. Changes are detected within 1-2 seconds
> of saving.

> **Why `--livereload`:** Forces live reload explicitly. Newer MkDocs versions stopped enabling
> it by default.

> **Why `--dirtyreload`:** Only rebuilds the single changed page instead of the entire site.
> Critical here because a full site rebuild takes over 100 seconds on this repository.

> **Why `--watch-theme`:** Ensures changes inside
> `.venv/.../material/templates` are also picked up, covering Material theme template changes.

### 7. Save as a shell alias

```bash
alias mkserve="WATCHDOG_FORCE_POLLING=1 mkdocs serve --livereload --dirtyreload --watch-theme"
```

Add to `~/.zshrc` so the command is available across sessions.

## Verification

Expected output after running the serve command:

```text
INFO    -  Documentation built in 106.92 seconds
INFO    -  [23:09:39] Watching paths for changes: '.', 'mkdocs.yml', 'docs/overrides',
           '.venv/lib/python3.14/site-packages/material/templates',
           '.venv/lib/python3.14/site-packages/mkdocs/templates',
           'docs/stylesheets'
INFO    -  [23:09:39] Serving on http://127.0.0.1:8000/
INFO    -  [23:11:50] Browser connected: http://localhost:8000/workstation/
INFO    -  [23:12:03] Detected file changes
```

All watched paths must appear in the `Watching paths for changes:` line. The `Detected file
changes` line confirms polling is active and file changes are being picked up across the full
directory tree without any manual browser refresh.

Failing indicator: if `Watching paths for changes:` does not appear at all after starting the
server, `click` has not been downgraded yet.

## Troubleshooting

### `Watching paths for changes:` line does not appear

**Cause:** `click` version is above `8.2.1`.

**Fix:**

```bash
pip show click
pip install "click==8.2.1"
```

### Server restarts in a loop immediately after starting

**Cause:** `site_dir` is inside `docs_dir: .`, causing build output to trigger re-watches.

**Fix:** Set `site_dir: /tmp/mkdocs-runbook/` in `mkdocs.yml`.

### Changes to CSS or theme overrides do not trigger reload

**Cause:** `watch:` block is missing from `mkdocs.yml` and `--watch-theme` flag is not passed.

**Fix:** Add the `watch:` block (Step 3) and use the full serve command (Step 6).

### Content file changes detected in terminal but browser does not refresh

**Cause:** `watchdog` FSEvents backend on macOS misses changes in large directory trees.

**Fix:**

```bash
pip install "watchdog[watchmedo]"
WATCHDOG_FORCE_POLLING=1 mkdocs serve --livereload --dirtyreload --watch-theme
```

## Key Decisions

- `WATCHDOG_FORCE_POLLING=1` was chosen over native FSEvents because the repository root
  contains `.venv/`, `.git/`, and all content folders together, making the FSEvents backend
  unreliable at this scale on macOS.
- `--dirtyreload` was chosen over standard reload because the full site build took 106 seconds.
  Dirty reload rebuilds only the changed page, making the feedback loop usable.
- `site_dir` was set to `/tmp/mkdocs-runbook/` rather than a relative path like `../site/` to
  ensure the output folder is never inside any watched directory on any machine.

## Related

- `workstation/macos/` - other macOS workstation tooling
