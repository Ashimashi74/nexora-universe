#!/usr/bin/env python3
"""CI-only project tweaks (run on the CI checkout, never committed back):
- enable the NexoraLiveKit editor plugin (so its EditorExportPlugin ships the AAR + maven deps)
- stamp version code/name from the run number
- export hygiene: exclude tests/, shots/, plugin_src/, *.md; compress native libs
- textures: lossy WebP (quality 0.75) instead of lossless for every 2D texture import
- add two more presets cloned from "Android": "Android AAB" (export_format=1) and "Android arm64"
"""
import glob, os, re

run = os.environ.get("GITHUB_RUN_NUMBER", "1")

# ---- project.godot: editor plugin
p = "project.godot"
s = open(p, encoding="utf-8").read()
want = "res://addons/nexora_livekit/plugin.cfg"
if want not in s:
    if "[editor_plugins]" in s:
        s = re.sub(r'(\[editor_plugins\][^\[]*?enabled=PackedStringArray\()', r'\1"%s", ' % want, s, count=1)
        s = s.replace(', )', ')')
    else:
        s = s.rstrip("\n") + '\n\n[editor_plugins]\n\nenabled=PackedStringArray("%s")\n' % want
    open(p, "w", encoding="utf-8").write(s)
    print("enabled editor plugin")

# ---- textures: lossy webp
n = 0
for f in glob.glob("**/*.import", recursive=True):
    if f.startswith(("shots/", "tests/", "plugin_src/")):
        continue
    t = open(f, encoding="utf-8").read()
    if 'importer="texture"' not in t:
        continue
    t2 = re.sub(r'(?m)^compress/mode=0$', 'compress/mode=1', t)
    t2 = re.sub(r'(?m)^compress/lossy_quality=.*$', 'compress/lossy_quality=0.75', t2)
    if t2 != t:
        open(f, "w", encoding="utf-8").write(t2)
        n += 1
print("textures switched to lossy webp:", n)

# ---- export presets
e = "export_presets.cfg"
t = open(e, encoding="utf-8").read()
def setopt(block, key, val):
    pat = r'(?m)^%s=.*$' % re.escape(key)
    if re.search(pat, block):
        return re.sub(pat, "%s=%s" % (key, val), block)
    return block.rstrip("\n") + "\n%s=%s\n" % (key, val)

m = re.search(r'(?s)\[preset\.0\]\n(.*?)\n\[preset\.0\.options\]\n(.*?)(?=\n\[preset\.\d|\Z)', t)
head, opts = m.group(1), m.group(2)
head = setopt(head, "exclude_filter", '"tests/*, shots/*, plugin_src/*, *.md, android/keys/*"')
opts = setopt(opts, "version/code", run)
opts = setopt(opts, "version/name", '"2.0.%s"' % run)
opts = setopt(opts, "gradle_build/compress_native_libraries", "true")
opts = setopt(opts, "gradle_build/export_format", "0")
opts = setopt(opts, "gradle_build/min_sdk", '"24"')
opts = setopt(opts, "gradle_build/target_sdk", '"35"')
opts = setopt(opts, "permissions/custom_permissions", "PackedStringArray()")
opts = setopt(opts, "package/signed", "true")
opts = setopt(opts, "package/signed", "true")
for a in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64"):
    opts = setopt(opts, "architectures/" + a, "true")

def preset(i, name, o):
    h = setopt(head, "name", '"%s"' % name)
    if i > 0:
        h = setopt(h, "runnable", "false")
    return "[preset.%d]\n%s\n\n[preset.%d.options]\n%s\n" % (i, h.strip("\n"), i, o.strip("\n"))

aab = setopt(opts, "gradle_build/export_format", "1")
arm = opts
for a in ("armeabi-v7a", "x86", "x86_64"):
    arm = setopt(arm, "architectures/" + a, "false")
out = preset(0, "Android", opts) + "\n" + preset(1, "Android AAB", aab) + "\n" + preset(2, "Android arm64", arm)
open(e, "w", encoding="utf-8").write(out)
print(out)
