# macOS Git: Suppressing .DS_Store and .turd_MacPorts Globally

## Context

macOS generates `.DS_Store` (Finder metadata) and `.turd_MacPorts` (MacPorts
directory placeholder) in any directory touched by those tools. Both appear in
`git status` with no project relevance. They are suppressed via a global gitignore
so no project `.gitignore` is polluted with machine-specific entries.

## Prerequisites

- Git installed on macOS
- Terminal access

## Steps

```bash
# Create global gitignore and register it
cat >> ~/.gitignore_global << 'EOF'
.DS_Store
**/.DS_Store
.turd_MacPorts
EOF

git config --global core.excludesfile ~/.gitignore_global
```

> **Why `**/.DS_Store` in addition to `.DS_Store`:** A bare entry matches only the
> repo root. The `**/` prefix matches at any subdirectory depth.

> **Why global, not project-level:** Both files are OS/toolchain artifacts. A project
> `.gitignore` is for files the project generates. Mixing them forces teammates on
> other OSes to carry irrelevant entries.

If `.DS_Store` was already committed to a repo:

```bash
git rm --cached .DS_Store
git rm --cached -r --ignore-unmatch **/.DS_Store
git commit -m "chore: remove .DS_Store from tracking"
```

> **Why `--cached`:** Removes the file from Git's index without deleting it from disk.

## Verification

```bash
git config --global core.excludesfile
```

Expected:
```text
/Users/ibtisam/.gitignore_global
```

```bash
git check-ignore -v .DS_Store
```

Expected:
```text
/Users/ibtisam/.gitignore_global:1:.DS_Store    .DS_Store
```

If `git check-ignore` returns nothing, `core.excludesfile` is not set or points
to the wrong path.

## Troubleshooting

### `.DS_Store` still appears in `git status` after adding the ignore rule

**Cause:** The file was already tracked before the rule was added. Global ignore
rules only apply to untracked files.
**Fix:** `git rm --cached .DS_Store` inside the affected repo, then commit.

## Related

- [gitignore - Git documentation](https://git-scm.com/docs/gitignore)
- [MacPorts Guide](https://guide.macports.org)
