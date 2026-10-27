"""MkDocs build hook: register dotfile nav configs and pin top-level tab order.

Layout uses `docs_dir: .` + same-dir plugin. Under this config, awesome-nav
does not load the root `.nav.yml` (lukasgeiter/mkdocs-awesome-nav#130), so
top-level tab order is set here in on_nav instead.
"""

from mkdocs.plugins import event_priority
from mkdocs.structure.files import File
import pathlib

# Pinned tabs, in order. Home is forced first separately (see on_nav).
# Match rendered titles exactly: "Self Hosted", "IaC".
PINNED_TITLES = ["Projects"]


@event_priority(100)
def on_files(files, config, **kwargs):
    # MkDocs drops dotfiles, which would hide every `.nav.yml`. Re-add them so
    # awesome-nav can read per-directory section configs.
    docs_dir = config["docs_dir"]
    existing = {f.src_path for f in files}
    for nav_file in pathlib.Path(docs_dir).rglob(".nav.yml"):
        src = str(nav_file.relative_to(docs_dir))
        if src not in existing:
            files.append(File(src, docs_dir, config["site_dir"], False))
    return files


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