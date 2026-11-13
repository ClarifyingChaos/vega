#!/usr/bin/env python3
# Licensed under GPL-3.0. See LICENSE.
#
# Turns VEGA_CHANGELOG.md into a Swift string the Updates page shows, so the in-app list of
# changes can't drift from the changelog and works offline. Run by scripts/release.sh before the build.

import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
text = (root / "VEGA_CHANGELOG.md").read_text()
assert '"""#' not in text
out = root / "Nook/Components/Settings/Tabs/ChangelogData.swift"
out.write_text(f'''// Licensed under GPL-3.0. See LICENSE.
// Generated from VEGA_CHANGELOG.md by scripts/gen-changelog.py. Do not edit.

let vegaChangelogMarkdown = #"""
{text.rstrip()}
"""#
''')
print(f"wrote {out.relative_to(root)}")
