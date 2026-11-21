#!/usr/bin/env python3
"""
Writes assets/tres/audio/sfx_bank.tres: one SfxDef per sound id (the files assets/sfx/**/<id>[_N].wav|ogg
are its variants) with the starting numbers below, plus each map's ambience. Run it after build_sfx.py adds
a sound. It refuses to overwrite an existing bank (those numbers get tuned by hand in the editor) unless
given --force; then the tuned values are lost.
"""
import glob, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "tres", "audio", "sfx_bank.tres")

# id prefix -> (bus, volume_db, jitter_db, pitch_min, pitch_max, max_voices, min_interval, positional, unit_size, max_distance)
SFX, UI, AMB = "SFX", "UI", "Ambience"
def W(vol, vox, unit, dist, jit=1.0, p=(0.95, 1.05), gap=0.0, bus=SFX): return (bus, vol, jit, p[0], p[1], vox, gap, True, unit, dist)
def F(vol, vox=1, jit=0.0, p=(1.0, 1.0), gap=0.0, bus=SFX): return (bus, vol, jit, p[0], p[1], vox, gap, False, 1.0, 100.0)
CFG = {
    "step_concrete": W(-2, 8, 4, 45, 2.0, (0.92, 1.08), 0.05), "step_grass": W(-2, 8, 4, 45, 2.0, (0.92, 1.08), 0.05),
    "step_wood": W(-1, 8, 4, 45, 2.0, (0.92, 1.08), 0.05),
    "jump": W(-3, 5, 5, 50, 1.5, (0.95, 1.1), 0.05), "land_light": W(-4, 5, 7, 60, 1.5, (0.9, 1.1), 0.05),
    "land_heavy": W(0, 4, 9, 80, 1.0, (0.9, 1.05), 0.08), "dash": W(-2, 4, 8, 70, 1.0, (0.95, 1.1), 0.1),
    "wall_jump": W(-2, 4, 6, 55, 1.0, (0.95, 1.08), 0.08), "slam_start": W(-2, 3, 8, 70, 1.0, (0.95, 1.05), 0.2),
    "slam_land": W(1, 3, 14, 110, 1.0, (0.92, 1.04), 0.15), "vault": W(-3, 4, 5, 50, 1.5, (0.95, 1.08), 0.1),
    "skid": W(-2, 3, 6, 50, 1.5, (0.9, 1.1), 0.12), "brake_air": W(-3, 3, 7, 60, 1.0, (0.95, 1.05), 0.2),
    "bonk": W(6, 4, 8, 70, 1.5, (0.92, 1.05), 0.1), "pad_launch": W(0, 3, 9, 70, 1.0, (0.95, 1.05), 0.1),
    "slide_loop": W(-4, 4, 5, 40, 0.0, (1.0, 1.0)), "wall_slide_loop": W(-4, 3, 5, 40, 0.0, (1.0, 1.0)),
    "wind_speed": F(-6, 1),
    "ignite": W(1, 4, 12, 90, 1.0, (0.93, 1.06), 0.1), "torch_loop": W(-6, 3, 6, 50, 0.0, (1.0, 1.0)),
    "smolder_loop": W(-4, 3, 5, 40, 0.0, (1.0, 1.0)), "extinguish": W(-2, 3, 8, 60, 1.0, (0.95, 1.05), 0.1),
    "smoke_warn": W(0, 2, 15, 120, 0.5, (0.97, 1.03), 0.5), "shove": W(0, 4, 8, 70, 1.5, (0.93, 1.07), 0.08),
    "fuse_tick": W(-1, 2, 10, 80, 0.5, (1.0, 1.0), 0.05), "fuse_loop": W(-9, 1, 6, 60, 0.0, (1.0, 1.0)),
    "explosion": W(2, 3, 30, 200, 1.0, (0.94, 1.04), 0.2),
    "storm_start": F(0, 1), "storm_loop": F(-5, 1, bus=AMB),
    "countdown_beep": F(-2, 1), "countdown_go": F(-1, 1), "win": F(-2, 1), "lose": F(-2, 1),
    "lava_in": W(-1, 3, 10, 80, 1.0, (0.95, 1.05), 0.2),
    "amb_": F(0, 1, bus=AMB),
    "ui_hover": F(-9, 2, 1.0, (0.97, 1.03), 0.04, UI), "ui_click": F(-4, 3, 0.5, (0.97, 1.03), 0.03, UI),
    "ui_back": F(-4, 2, 0.0, (1.0, 1.0), 0.05, UI), "ui_confirm": F(-3, 2, 0.0, (1.0, 1.0), 0.1, UI),
    "ui_toggle": F(-4, 2, 0.5, (0.98, 1.02), 0.03, UI), "ui_tick": F(-9, 3, 1.0, (0.95, 1.08), 0.03, UI),
    "ui_turn": F(-6, 3, 1.0, (0.95, 1.05), 0.05, UI), "ui_whoosh": F(-6, 2, 1.0, (0.97, 1.03), 0.1, UI),
    "ui_pop": F(-6, 6, 1.5, (0.9, 1.15), 0.0, UI), "ui_open": F(-6, 2, 0.0, (1.0, 1.0), 0.1, UI),
    "ui_close": F(-6, 2, 0.0, (1.0, 1.0), 0.1, UI),
}
LOOPS = {"slide_loop", "wall_slide_loop", "wind_speed", "torch_loop", "smolder_loop", "fuse_loop", "storm_loop"}
# map name -> (surface, [(ambience id, dB)])
MAPS = {
    "test_gym": ("concrete", [("amb_wind", -14)]),
    "overworld": ("grass", [("amb_plains", -4)]),
    "jungle": ("wood", [("amb_jungle", -4), ("amb_lava", -18)]),
    "inferno": ("concrete", [("amb_hall", -8), ("amb_lava", -6), ("amb_wind", -22)]),
}


def main():
    if os.path.exists(OUT) and "--force" not in sys.argv:
        raise SystemExit("%s exists (its numbers are hand-tuned): pass --force to rewrite it" % os.path.relpath(OUT, ROOT))
    groups = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "assets", "sfx", "*", "*.*"))):
        if f.endswith(".import"): continue
        name = os.path.splitext(os.path.basename(f))[0]
        groups.setdefault(re.sub(r"_\d+$", "", name), []).append(f)
    ext, subs, n = [], [], 0
    ext.append('[ext_resource type="Script" path="res://src/audio/sfx_bank.gd" id="1_bank"]')
    ext.append('[ext_resource type="Script" path="res://src/audio/sfx_def.gd" id="2_def"]')
    ext.append('[ext_resource type="Script" path="res://src/audio/map_audio.gd" id="3_map"]')
    def_ids, map_ids = [], []
    for sid, files in groups.items():
        key = sid if sid in CFG else ("amb_" if sid.startswith("amb_") else None)
        if key is None: raise SystemExit("no config for sound '%s'" % sid)
        bus, vol, jit, p0, p1, vox, gap, pos, unit, dist = CFG[key]
        refs = []
        for f in files:
            n += 1
            rid = "s%d" % n
            ext.append('[ext_resource type="AudioStream" path="res://%s" id="%s"]' % (os.path.relpath(f, ROOT).replace(os.sep, "/"), rid))
            refs.append('ExtResource("%s")' % rid)
        did = "d_" + sid
        def_ids.append('SubResource("%s")' % did)
        subs.append('\n'.join([
            '[sub_resource type="Resource" id="%s"]' % did, 'script = ExtResource("2_def")', 'id = &"%s"' % sid,
            'streams = Array[AudioStream]([%s])' % ", ".join(refs), 'bus = &"%s"' % bus, 'volume_db = %s' % float(vol),
            'volume_jitter_db = %s' % jit, 'pitch_min = %s' % p0, 'pitch_max = %s' % p1, 'max_voices = %d' % vox,
            'min_interval = %s' % gap, 'positional = %s' % str(pos).lower(), 'unit_size = %s' % float(unit),
            'max_distance = %s' % float(dist), 'loop = %s' % str(sid in LOOPS or sid.startswith("amb_")).lower(), ""]))
    for mname, (surface, amb) in MAPS.items():
        mid = "m_" + mname
        map_ids.append('SubResource("%s")' % mid)
        subs.append('\n'.join([
            '[sub_resource type="Resource" id="%s"]' % mid, 'script = ExtResource("3_map")', 'map_name = &"%s"' % mname,
            'surface = &"%s"' % surface, 'ambience = Array[StringName]([%s])' % ", ".join('&"%s"' % a for a, _ in amb),
            'ambience_db = Array[float]([%s])' % ", ".join(str(float(d)) for _, d in amb), ""]))
    out = '[gd_resource type="Resource" script_class="SfxBank" load_steps=%d format=3]\n\n' % (len(ext) + len(subs) + 1)
    out += "\n".join(ext) + "\n\n" + "\n".join(subs) + "\n[resource]\nscript = ExtResource(\"1_bank\")\n"
    out += 'sounds = Array[ExtResource("2_def")]([%s])\n' % ", ".join(def_ids)
    out += 'maps = Array[ExtResource("3_map")]([%s])\n' % ", ".join(map_ids)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write(out)
    print("%d sounds, %d files, %d maps -> %s" % (len(groups), n, len(MAPS), os.path.relpath(OUT, ROOT)))


main()
