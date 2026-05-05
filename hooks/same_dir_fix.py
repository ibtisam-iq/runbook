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
