# MkDocs Awesome Nav + Same Dir: Root Tab Order Not Applied

## Context

The runbook site (`runbook.ibtisam-iq.com`) uses `docs_dir: .` with the `mkdocs-same-dir` plugin, so all content lives at the repository root. After resolving the v3 migration (see the companion runbook [MkDocs Awesome Nav + Same Dir: Navigation Not Loading After v3 Migration](debug-mkdocs-awesome-nav-same-dir.md)), per-directory section ordering worked — but **the top-level tab order would not change**.

I wanted the tabs to read **Home → Projects → (everything else, alphabetical)**. Pinning `projects` in the root `.nav.yml` had no effect. The site built cleanly, the config looked correct, yet the tabs stayed fully alphabetical with `Projects` stuck in its alphabetical slot.

!!! info "What this runbook is"
    The diagnostic path that proves `awesome-nav` does **not** load the *root* `.nav.yml` under `docs_dir: .` + `same-dir`, and the `on_nav` hook that fixes top-level tab order without touching the layout.

**Reference:** [awesome-nav#130 — root `.nav.yml` not loaded with same-dir](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130)

## What Was Done

| Item | Detail |
|---|---|
| Goal | Pin `Home` first, `Projects` second, rest alphabetical |
| Symptom | Root `.nav.yml` `nav:` order ignored; tabs stay alphabetical |
| Root cause | `awesome-nav` v3 does not load the **root** `.nav.yml` under `docs_dir: .` + `same-dir` (issue [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130)) |
| Why per-dir works but root doesn't | Section `.nav.yml` files are read from the file collection; the root config is resolved separately and misses |
| Resolution | Set top-level tab order in an `on_nav` hook that runs **after** `awesome-nav` |

## Conceptual Overview

`awesome-nav` resolves two different things:

- **Per-directory section configs** — read from the MkDocs file collection. The `same_dir_fix.py` hook re-injects stripped `.nav.yml` files into that collection, so these work.
- **The root navigation config** — resolved separately, relative to the docs root as MkDocs sees it *after* `same-dir` remaps paths. Under `docs_dir: .`, that resolution never lands on the filesystem-root `.nav.yml`.

The net effect: the root `nav:` block is silently inert. `append_unmatched` and per-directory ordering still work, but **top-level tab order falls back to alphabetical**. No warning is emitted, which is what makes this hard to spot.

!!! warning "The misleading part"
    The root `.nav.yml` *looks* like it controls tab order, and it does in a standard `docs/` layout. Under `docs_dir: .` + `same-dir` it does not. Leaving a `nav:` block there is dead config that hides the real control point.

## Prerequisites

- `mkdocs-awesome-nav` v3 installed
- `mkdocs-same-dir` installed
- `docs_dir: .` set in `mkdocs.yml`
- The `same_dir_fix.py` hook from the [companion runbook](debug-mkdocs-awesome-nav-same-dir.md) already in place
- Python `>= 3.x`, macOS (Apple Silicon)

## Diagnostic Path

The fix is only obvious once it is proven that the root config is ignored. These are the exact checks I ran, in order. Each one narrows the cause.

### 1. Confirm there is no `nav:` in `mkdocs.yml`

`awesome-nav` v3 ignores `nav:` in `mkdocs.yml` outright, so a leftover block there is a red herring.

```bash
grep -n "nav:" mkdocs.yml
```

Expected: no top-level `nav:` (only `validation.nav` and similar nested keys).

### 2. Confirm the target directory exists and matches

```bash
ls -d */ | grep projects
```

Expected: `projects/` present. No `awesome-nav: ... doesn't match` warning for it on build means the entry matches — yet the order still does not change. This rules out a name mismatch.

### 3. Inspect the built HTML — the ground truth

Browser caching and `navigation.instant` make the live page unreliable. The built HTML is the source of truth. The `minify` plugin strips attribute order, so match on the rendered class and label text:

```bash
mkdocs build --clean
python3 -c "
import re
html = open('site/index.html').read()
print([m for m in re.findall(r'md-tabs__link[^>]*>\s*([A-Za-z][A-Za-z ]+?)\s*<', html)])
"
```

Observed output — fully alphabetical, `Projects` not pinned:

```text
['Home', 'Bootstrap', 'Cloud', 'Containers', 'Delivery', 'IaC', 'Kubernetes',
 'Linux', 'Networking', 'Observability', 'Projects', 'Security', 'Self Hosted',
 'Storage', 'Workstation']
```

### 4. Prove the root config is read at all — directory reorder probe

A nonexistent-page entry can be silently dropped, so it is **not** a reliable probe. Instead, reference a **real directory** in a deliberately wrong position and check whether it moves:

```bash
cat > .nav.yml << 'EOF'
nav:
  - workstation
  - Home: index.md
  - projects
append_unmatched: true
EOF
mkdocs build --clean
python3 -c "
import re
html = open('site/index.html').read()
print([m for m in re.findall(r'md-tabs__link[^>]*>\s*([A-Za-z][A-Za-z ]+?)\s*<', html)])
"
```

`workstation` is pinned first. If the root config were read, `Workstation` would jump to position 1.

Observed — `Workstation` stayed last:

```text
['Home', 'Bootstrap', 'Cloud', 'Containers', 'Delivery', 'IaC', 'Kubernetes',
 'Linux', 'Networking', 'Observability', 'Projects', 'Security', 'Self Hosted',
 'Storage', 'Workstation']
```

!!! danger "Conclusion"
    The root `.nav.yml` is ignored. This is issue [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130), not a config error. No amount of root-config syntax will fix it. The fix must operate on the **final nav object**, after `awesome-nav` runs.

## The Fix

Set top-level tab order in `on_nav`, which runs after every plugin has built the nav tree. Add this to the existing `hooks/same_dir_fix.py`.

```python
@event_priority(-100)  # after awesome-nav, so we reorder the final nav
def on_nav(nav, config, files, **kwargs):
    def rank(item):
        # is_homepage, not title: the homepage title is unreliable here.
        if getattr(item, "is_page", False) and getattr(item, "is_homepage", False):
            return (0, -1)
        title = (item.title or "").strip()
        if title in PINNED_TITLES:
            return (0, PINNED_TITLES.index(title))
        return (1, 0)  # unpinned: keep awesome-nav order (stable sort)

    nav.items[:] = sorted(nav.items, key=rank)
    return nav
```

Define the pin list near the top of the file:

```python
# Pinned tabs, in order. Home is forced first separately (see on_nav).
# Match rendered titles exactly: "Self Hosted", "IaC".
PINNED_TITLES = ["Projects"]
```

!!! note "Why this works when root config does not"
    - **Priority `-100`** runs the hook late, on the finished nav — so the `#130` resolution issue is irrelevant; I never touch the root config path.
    - **`sorted()` is stable** — pinned tabs move to the front; every other tab keeps `awesome-nav`'s alphabetical order untouched.
    - **`is_homepage`, not title** — at this stage the homepage's title is not the literal string `"Home"`, so matching it by title pins `Projects` *ahead* of an unranked Home. Detecting the homepage structurally fixes that.

### Simplify the root `.nav.yml`

Since the root `nav:` block is inert, remove it. Leave only what the file genuinely controls — fallback inclusion and sort, both inherited by child directories:

```yaml
# awesome-nav root config.
# Note: under `docs_dir: .` + same-dir, the root nav: block is ignored
# (mkdocs-awesome-nav#130). Tab order lives in hooks/same_dir_fix.py.
# This file only sets fallback inclusion + sort for unplaced items.

append_unmatched: true   # include everything; inherited by child dirs

sort:
  type: natural
  direction: asc
  by: filename
  ignore_case: true
```

## Verification

```bash
mkdocs build --clean
python3 -c "
import re
html = open('site/index.html').read()
print([m for m in re.findall(r'md-tabs__link[^>]*>\s*([A-Za-z][A-Za-z ]+?)\s*<', html)])
"
```

Expected — `Home` first, `Projects` second, rest alphabetical:

```text
['Home', 'Projects', 'Bootstrap', 'Cloud', 'Containers', 'Delivery', 'IaC',
 'Kubernetes', 'Linux', 'Networking', 'Observability', 'Security',
 'Self Hosted', 'Storage', 'Workstation']
```

## Troubleshooting

### Root `.nav.yml` order ignored, no warning

**Cause:** `awesome-nav` does not load the root config under `docs_dir: .` + `same-dir` (issue [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130)).

**Fix:** Set tab order in the `on_nav` hook above, not in `.nav.yml`.

### Pinned tab lands ahead of Home

**Cause:** Matching the homepage by the title string `"Home"` fails — its title is unreliable in `on_nav`, so it falls into the unpinned bucket while the pinned tab sorts ahead of it.

**Fix:** Detect the homepage with `is_homepage`, not by title (as shown).

### A spurious `Docs` tab appears

**Cause:** Placing the root config at `docs/.nav.yml` makes `awesome-nav` treat the existing `docs/` folder (overrides, stylesheets, includes) as a content section.

**Fix:** Keep the root config at the repo root and do not rely on it for tab order; use the hook.

### Nonexistent-page probe shows no warning

**Cause:** A `nav:` entry pointing at a missing file can be dropped silently — it is not a reliable test of whether the config is read.

**Fix:** Probe with a **real directory** placed out of alphabetical order and check whether it moves (Step 4).

## Key Decisions

**`on_nav` hook over fighting the root config:** Issue [#130](https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130) is a structural incompatibility, not a syntax error. Reordering the final nav object is the only approach immune to it.

**Not moving content into `docs/`:** The `docs_dir: .` structure is intentional. Migrating every content folder to fix a plugin resolution quirk is collateral damage, not a fix.

**Removing the inert root `nav:` block:** Dead config that appears to control tab order is worse than no config — it hides the real control point. The root `.nav.yml` is kept only for `append_unmatched` and sort.

**Matching tabs by rendered title:** The pin list uses display titles (`"Self Hosted"`, `"IaC"`) so the control point reads the same as the tab bar. Title strings must match exactly.

## Related

- Companion runbook: [MkDocs Awesome Nav + Same Dir: Navigation Not Loading After v3 Migration](debug-mkdocs-awesome-nav-same-dir.md)
- Root config not loaded with same-dir: https://github.com/lukasgeiter/mkdocs-awesome-nav/issues/130
- Custom navigation reference: https://lukasgeiter.github.io/mkdocs-awesome-nav/features/nav/
- MkDocs plugin events (`on_files`, `on_nav`): https://www.mkdocs.org/dev-guide/plugins/#events
