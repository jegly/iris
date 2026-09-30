#!/usr/bin/env bash
# Iris — B7 part 2: clear text Iris copied from the clipboard after 30 s (2026-09-28). Only while "Delete browsing
# data automatically" is on (IrisShredder switches it; off by default).
# Every browser clipboard write (page copies via ClipboardHostImpl, omnibox, context menus) goes through
# ui::ScopedClipboardWriter. After a copy-paste-buffer write that contains text, a delayed task reads the clipboard
# and clears it ONLY if it still holds exactly that text: anything copied later, in Iris or another app, is left
# alone. (Content comparison, not the sequence number: on Wayland the compositor echoes our own write back as a
# change at an unpredictable time.) Images/files-only copies are not cleared.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

h = "ui/base/clipboard/scoped_clipboard_writer.h"
edit(h, "  ~ScopedClipboardWriter();\n",
     "  ~ScopedClipboardWriter();\n\n"
     "  // Iris (B7): when set, text written to the copy-paste clipboard is cleared\n"
     "  // after `delay` if the clipboard still holds exactly that text\n"
     "  // (apply-clipboard-clear.sh). std::nullopt = off (default).\n"
     "  static void SetIrisClearCopiedTextAfter(\n"
     "      std::optional<base::TimeDelta> delay);\n",
     "SetIrisClearCopiedTextAfter", "declaration")
edit(h, '#include "base/containers/flat_map.h"\n',
     '#include "base/containers/flat_map.h"\n#include "base/time/time.h"  // Iris (B7)\n',
     '#include "base/time/time.h"  // Iris (B7)', "include time")

hs = open(h).read()
if "#include <optional>\n" not in hs:
    hs = hs.replace("#include <string>\n", "#include <optional>\n#include <string>\n", 1); open(h, "w").write(hs); print("OK   %s : <optional>" % h)

c = "ui/base/clipboard/scoped_clipboard_writer.cc"
edit(c, "ScopedClipboardWriter::ScopedClipboardWriter(\n",
     "namespace {\n\n"
     "// Iris (B7): see SetIrisClearCopiedTextAfter(). UI thread only.\n"
     "std::optional<base::TimeDelta> g_iris_clear_after;\n\n"
     "void IrisClearIfStillCopied(std::u16string copied) {\n"
     "  Clipboard* clipboard = Clipboard::GetForCurrentThread();\n"
     "  if (!clipboard) {\n    return;\n  }\n"
     "  clipboard->ReadText(\n"
     "      ClipboardBuffer::kCopyPaste, /*data_dst=*/std::nullopt,\n"
     "      base::BindOnce(\n"
     "          [](std::u16string copied, std::u16string now) {\n"
     "            if (now == copied) {\n"
     "              Clipboard::GetForCurrentThread()->Clear(\n"
     "                  ClipboardBuffer::kCopyPaste);\n"
     "            }\n"
     "          },\n"
     "          std::move(copied)));\n"
     "}\n\n"
     "}  // namespace\n\n"
     "// static\n"
     "void ScopedClipboardWriter::SetIrisClearCopiedTextAfter(\n"
     "    std::optional<base::TimeDelta> delay) {\n"
     "  g_iris_clear_after = delay;\n"
     "}\n\n"
     "ScopedClipboardWriter::ScopedClipboardWriter(\n",
     "g_iris_clear_after", "clear helper")
edit(c, "        std::move(platform_representations_), std::move(data_src_),\n"
        "        privacy_types_);\n  }\n}\n",
     "        std::move(platform_representations_), std::move(data_src_),\n"
     "        privacy_types_);\n\n"
     "    // Iris (B7): schedule the clear for copied text.\n"
     "    auto text_iter = objects_.find(\n"
     "        base::VariantIndexOfType<Clipboard::Data, Clipboard::TextData>());\n"
     "    if (g_iris_clear_after && buffer_ == ClipboardBuffer::kCopyPaste &&\n"
     "        text_iter != objects_.end()) {\n"
     "      std::u16string copied = base::UTF8ToUTF16(\n"
     "          std::get<Clipboard::TextData>(text_iter->second.data).data);\n"
     "      if (!copied.empty()) {\n"
     "        base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(\n"
     "            FROM_HERE, base::BindOnce(&IrisClearIfStillCopied, std::move(copied)),\n"
     "            *g_iris_clear_after);\n"
     "      }\n"
     "    }\n  }\n}\n",
     "Iris (B7): schedule the clear", "schedule clear")
s = open(c).read()
for inc in ('#include "base/functional/bind.h"\n', '#include "base/task/sequenced_task_runner.h"\n',
            '#include "base/strings/utf_string_conversions.h"\n'):
    if inc not in s:
        anchor = '#include "ui/base/clipboard/scoped_clipboard_writer.h"\n'
        if s.count(anchor) != 1: die(c + ": include anchor missing")
        s = s.replace(anchor, anchor + inc, 1)
        print("OK   %s : %s" % (c, inc.strip()))
open(c, "w").write(s)
PY
python3 - <<'PY'
p = "chrome/app/settings_strings.grdp"
s = open(p).read()
old = "Cookies and site data after 24 hours, cached files after 12 hours, the downloads list after 7 days."
new = "Cookies and site data after 24 hours, cached files after 12 hours, the downloads list after 7 days, and text copied in Iris from the clipboard after 30 seconds."
if new in s: print("SKIP already applied: " + p + " (sub-label)")
elif s.count(old) == 1: open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : sub-label mentions the clipboard")
else: raise SystemExit("ERROR: " + p + ": shredding sub-label not found (run apply-iris-permissions.sh first)")
PY
echo "=== clipboard clear (B7) complete ==="
