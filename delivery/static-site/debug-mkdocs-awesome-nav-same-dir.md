# MkDocs Awesome Nav + Same Dir: Navigation Not Loading After v3 Migration

## Context

The runbook site (`runbook.ibtisam-iq.com`) uses `docs_dir: .` with the `mkdocs-same-dir` plugin so all markdown content lives at the repository root without a separate `docs/` folder. After migrating from `mkdocs-awesome-pages-plugin` to `mkdocs-awesome-nav` v3, navigation defined in `.pages` files was silently ignored — the site built without errors but custom nav order and titles were not applied.

**Reference:** [Official v3 Migration Guide](https://lukasgeiter.github.io/mkdocs-awesome-nav/migration-v3/)

## What Was Done

| Item | Detail |
|---|---|
| Plugin migrated from | `mkdocs-awesome-pages-plugin` |
| Plugin migrated to | `mkdocs-awesome-nav` v3 |
| Root cause 1 | `.pages` filename not recognized by `awesome-nav` v3 (default is `.nav.yml`) |
| Root cause 2 | `...` rest pattern removed in v3, replaced by `"*"` glob |
| Root cause 3 | `mkdocs-same-dir` strips `.nav.yml` files before `awesome-nav` can read them — open bug [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130) |
| Resolution | Renamed all `.pages` to `.nav.yml`, replaced `...` with `"*"`, added a MkDocs hook provided by the plugin maintainer to re-inject `.nav.yml` files stripped by `same-dir` |

## Conceptual Overview

`mkdocs-same-dir` intercepts the MkDocs file collection phase and filters out non-markdown files from the root so they are not rendered as documentation pages. In v3, `awesome-nav` changed its default filename from `.pages` to `.nav.yml`. Because `same-dir` strips dot-files it does not recognize, `.nav.yml` files are removed before `awesome-nav` reads them.

This is tracked as open issue [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130). The `same-dir` plugin is unmaintained — the original author has left the ecosystem. The plugin maintainer (`lukasgeiter`) provided a MkDocs hook as the official workaround.

### Filename and Plugin Config Relationship

| File name used | Plugin config required |
|---|---|
| `.pages` | `- awesome-nav:` <br>&nbsp;&nbsp;`filename: .pages` |
| `.nav.yml` (v3 default) | `- awesome-nav` (no extra config needed) |

## Prerequisites

- `mkdocs-awesome-nav` v3 installed
- `mkdocs-same-dir` installed
- `docs_dir: .` set in `mkdocs.yml`
- Existing `.pages` files throughout the repository

## Steps

### 1. Rename all `.pages` files to `.nav.yml`

```bash
find . -name ".pages" -not -path "./.venv/*" \
  -exec sh -c 'mv "$1" "$(dirname "$1")/.nav.yml"' _ {} \;
```

### 2. Replace `...` with `"*"` in all `.nav.yml` files

The `...` rest pattern was removed in v3. The direct replacement is the glob `"*"`.

```bash
find . -name ".nav.yml" -not -path "./.venv/*" \
  -exec sed -i '' 's/  - \.\.\./  - "*"/g' {} \;
```

> **Note — `sed` on Apple Silicon (M4 Mac):** The standard `sed -i ''` command may fail on M4 Macs. If you get an error, use `gsed` (GNU sed) instead:
> ```bash
> brew install gnu-sed
> find . -name ".nav.yml" -not -path "./.venv/*" \
>   -exec gsed -i 's/  - \.\.\./  - "*"/g' {} \;
> ```

### 3. Verify `.nav.yml` file structure

Each `.nav.yml` file must use `nav:` with quoted glob for the rest:

```yaml
title: Section Title
nav:
  - index.md
  - subsection/
  - "*"
```

> **Why `nav:` not `arrange:`:** `arrange:` was the v2/`awesome-pages` syntax and has been removed in v3.
> **Why quoted `"*"`:** The `*` character is a special character in YAML. Quoting prevents parse errors.

### 4. Add the hook to fix `same-dir` stripping `.nav.yml`

Create `hooks/same_dir_fix.py` in the repository root:

```python
from mkdocs.plugins import event_priority
from mkdocs.structure.files import File
import pathlib

@event_priority(100)
def on_files(files, config, **kwargs):
    docs_dir = config["docs_dir"]
    existing = {f.src_path for f in files}
    for nav_file in pathlib.Path(docs_dir).rglob(".nav.yml"):
        src = str(nav_file.relative_to(docs_dir))
        if src not in existing:
            files.append(File(src, docs_dir, config["site_dir"], False))
    return files
```

Register it in `mkdocs.yml`:

```yaml
hooks:
  - hooks/same_dir_fix.py
```

> **What this does:** `same-dir` removes `.nav.yml` files during file collection before `awesome-nav` processes them. This hook runs after `same-dir` at priority 100 and re-injects any `.nav.yml` files that were stripped, making them visible to `awesome-nav` again.

### 5. Plugin config in `mkdocs.yml`

Since files are now `.nav.yml` (the v3 default), no extra `filename` option is needed:

```yaml
plugins:
  - awesome-nav
```

## Verification

```bash
mkdocs serve --clean
```

Expected output — no navigation warnings, fast build, no `.venv` git-revision spam:

```text
INFO    -  Building documentation...
INFO    -  Cleaning site directory
INFO    -  Documentation built in X seconds
INFO    -  [HH:MM:SS] Watching paths for changes: '.', 'mkdocs.yml'
INFO    -  [HH:MM:SS] Serving on http://127.0.0.1:8000/
```

The sidebar reflects the order and titles defined in `.nav.yml` files. No `404` errors for JavaScript. No `.venv` packages processed as documentation.

## Troubleshooting

### Navigation order ignored after renaming to `.nav.yml`

**Cause:** `mkdocs-same-dir` strips `.nav.yml` files during file collection (issue [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130)).

**Fix:** Add the hook `hooks/same_dir_fix.py` described in Step 4.

### `sed` command fails on M4 Mac

**Cause:** BSD `sed` on macOS handles escape sequences differently from GNU `sed`.

**Fix:** Install GNU sed via Homebrew (`brew install gnu-sed`) and use `gsed` instead.

### Hundreds of git-revision warnings from `.venv` packages

**Cause:** `exclude_docs` paths not properly indented under the `|` block scalar.

**Fix:** Ensure each excluded path is indented with two spaces under `exclude_docs: |`.

### `...` entries ignored or cause errors

**Cause:** `...` rest pattern removed in `awesome-nav` v3.

**Fix:** Replace all `...` with `"*"` (quoted).

## Key Decisions

**Renaming to `.nav.yml` over keeping `.pages`:** Staying aligned with the v3 default is the correct long-term direction. The `same-dir` stripping issue is addressed by the hook, not by reverting the filename.

**Hook over downgrading `awesome-pages`:** The `awesome-pages` plugin is at end of life. Downgrading is the wrong direction. The hook is a 10-line, one-time fix.

**Not moving content into `docs/`:** The `docs_dir: .` structure is intentional. Moving all content folders would be a large structural change that solves a plugin bug via collateral damage.

## Related

- Official v3 Migration Guide: https://lukasgeiter.github.io/mkdocs-awesome-nav/migration-v3/
- `same-dir` + `awesome-nav` v3 bug: https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130
