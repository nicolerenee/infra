#!/usr/bin/env python3
"""Generate llms.txt and llms-full.txt from the docs/ directory.

Produces two files in the Zensical build output (site/):
  - llms.txt:      structured index with page descriptions (per llmstxt.org spec)
  - llms-full.txt: full concatenated content of all pages

Run after `zensical build` so the output lands in site/ alongside the HTML.
"""

import re
import sys
from pathlib import Path

DOCS_DIR = Path("docs")
SITE_DIR = Path("site")
SITE_URL = "https://infra-docs.nicole.dev"

# Section ordering and display names. Pages are grouped by their top-level
# directory. Pages at the docs root go into the section matching their stem,
# or "Reference" as a fallback.
SECTION_ORDER = [
    "Sites",
    "Compute",
    "Networking",
    "Storage",
    "Guides",
    "Reference",
]

DIR_TO_SECTION = {
    "sites": "Sites",
    "compute": "Compute",
    "networking": "Networking",
    "storage": "Storage",
    "guides": "Guides",
}


def extract_front_matter(text: str) -> tuple[dict[str, str], str]:
    """Extract YAML front matter and return (metadata dict, body)."""
    metadata = {}
    body = text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            for line in parts[1].strip().splitlines():
                if ":" in line:
                    key, _, value = line.partition(":")
                    metadata[key.strip()] = value.strip().strip('"').strip("'")
            body = parts[2].strip()
    return metadata, body


def extract_title(body: str) -> str:
    """Extract the first H1 heading from markdown body."""
    for line in body.splitlines():
        if line.startswith("# ") and not line.startswith("##"):
            return line[2:].strip()
    return ""


def md_path_to_url(md_path: Path) -> str:
    """Convert a docs/ markdown path to its published URL."""
    rel = md_path.relative_to(DOCS_DIR)
    if rel.name == "index.md":
        url_path = str(rel.parent) + "/"
        if url_path == "./":
            url_path = ""
    else:
        url_path = str(rel.with_suffix("")) + "/"
    return f"{SITE_URL}/{url_path}"


def classify_page(md_path: Path) -> str:
    """Determine which section a page belongs to."""
    rel = md_path.relative_to(DOCS_DIR)
    parts = rel.parts
    if len(parts) == 1:
        # Root-level file
        return "Reference"
    return DIR_TO_SECTION.get(parts[0], "Reference")


def strip_admonitions(body: str) -> str:
    """Remove MkDocs/Zensical admonition blocks (!!! type) from body text."""
    lines = body.splitlines()
    result = []
    in_admonition = False
    for line in lines:
        if re.match(r"^!!! \w+", line):
            in_admonition = True
            continue
        if in_admonition:
            if line.startswith("    ") or line.strip() == "":
                continue
            in_admonition = False
        result.append(line)
    return "\n".join(result)


def main():
    if not DOCS_DIR.exists():
        print(f"Error: {DOCS_DIR} not found", file=sys.stderr)
        sys.exit(1)

    SITE_DIR.mkdir(parents=True, exist_ok=True)

    # Collect all markdown files (skip CNAME and other non-doc files)
    md_files = sorted(
        p for p in DOCS_DIR.rglob("*.md")
        if p.name != "CNAME"
    )

    # Parse all pages
    pages = []
    for md_path in md_files:
        text = md_path.read_text()
        metadata, body = extract_front_matter(text)
        title = extract_title(body)
        description = metadata.get("description", "")
        section = classify_page(md_path)
        url = md_path_to_url(md_path)

        pages.append({
            "path": md_path,
            "title": title,
            "description": description,
            "section": section,
            "url": url,
            "body": body,
        })

    # Skip the root index from the section listings (it becomes the header)
    root_index = None
    section_pages = []
    for page in pages:
        rel = page["path"].relative_to(DOCS_DIR)
        if rel == Path("index.md"):
            root_index = page
        else:
            section_pages.append(page)

    # Skip short section index pages (navigational only) but keep index
    # pages with substantial content (like the fairy site page).
    content_pages = [
        p for p in section_pages
        if p["path"].name != "index.md" or len(p["body"]) > 500
    ]

    # --- Generate llms.txt ---
    lines = []
    lines.append("# Infra Documentation")
    lines.append("")

    if root_index:
        _, body = extract_front_matter(root_index["path"].read_text())
        # Pull the first paragraph (after the H1) as the blockquote
        body_clean = strip_admonitions(body)
        paragraphs = [
            p.strip() for p in body_clean.split("\n\n")
            if p.strip() and not p.strip().startswith("#")
        ]
        if paragraphs:
            for para_line in paragraphs[0].splitlines():
                lines.append(f"> {para_line}")
            lines.append("")

    # Group pages by section
    sections: dict[str, list[dict]] = {s: [] for s in SECTION_ORDER}
    for page in content_pages:
        section = page["section"]
        if section not in sections:
            sections[section] = []
        sections[section].append(page)

    for section_name in SECTION_ORDER:
        section_list = sections.get(section_name, [])
        if not section_list:
            continue
        lines.append(f"## {section_name}")
        lines.append("")
        for page in section_list:
            entry = f"- [{page['title']}]({page['url']})"
            if page["description"]:
                entry += f": {page['description']}"
            lines.append(entry)
        lines.append("")

    llms_txt = "\n".join(lines)
    (SITE_DIR / "llms.txt").write_text(llms_txt)
    print(f"Generated llms.txt ({len(content_pages)} pages)")

    # --- Generate llms-full.txt ---
    full_lines = []
    full_lines.append("# Infra Documentation — Full Content")
    full_lines.append("")

    for page in pages:
        full_lines.append(f"## {page['title']}")
        full_lines.append(f"Source: {page['url']}")
        full_lines.append("")
        # Strip front matter, keep the body as-is
        full_lines.append(page["body"])
        full_lines.append("")
        full_lines.append("---")
        full_lines.append("")

    llms_full_txt = "\n".join(full_lines)
    (SITE_DIR / "llms-full.txt").write_text(llms_full_txt)
    print(f"Generated llms-full.txt ({len(llms_full_txt)} chars)")


if __name__ == "__main__":
    main()
