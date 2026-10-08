import re

FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
MARKDOWN_SUFFIXES = (".md", ".mdx")


# The lines of a Markdown or MDX text that are outside its fenced code blocks, with their numbers from 1.
# A block opens with three or more backticks or tildes, and closes with a line of the same character, at least as long.
def lines_outside_code_blocks(text):
    fence = None
    for number, line in enumerate(text.split("\n"), start=1):
        opening = FENCE.match(line)
        if fence:
            if opening and opening.group(1)[0] == fence[0] and len(opening.group(1)) >= len(fence) \
                    and not line[opening.end():].strip():
                fence = None
            continue
        if opening:
            fence = opening.group(1)
            continue
        yield number, line
