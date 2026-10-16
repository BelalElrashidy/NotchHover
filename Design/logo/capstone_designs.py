import math

def pt(cx, cy, radius, deg):
    a = math.radians(deg)
    return (cx + radius * math.cos(a), cy - radius * math.sin(a))

def f(p):
    return f"{p[0]:.2f} {p[1]:.2f}"

def arch_halves(cx, cy, R, r, theta, gap, leg_bottom, foot=3):
    """Two continuous arch-plus-leg shapes, split by a radial keystone slot."""
    ga = math.degrees(gap / ((R + r) / 2))
    halves = []
    for sign in (+1, -1):
        edge = 90 + sign * (theta + ga)
        outer, inner = pt(cx, cy, R, edge), pt(cx, cy, r, edge)
        xo, xi = cx - sign * R, cx - sign * r
        so, si = (1, 0) if sign > 0 else (0, 1)
        halves.append(
            f"M {xo:.2f} {cy:.2f} A {R} {R} 0 0 {so} {f(outer)} L {f(inner)} "
            f"A {r} {r} 0 0 {si} {xi:.2f} {cy:.2f} L {xi:.2f} {leg_bottom - foot:.2f} "
            f"Q {xi:.2f} {leg_bottom:.2f} {xi - sign * foot:.2f} {leg_bottom:.2f} "
            f"L {xo + sign * foot:.2f} {leg_bottom:.2f} Q {xo:.2f} {leg_bottom:.2f} {xo:.2f} {leg_bottom - foot:.2f} Z"
        )
    return halves

def keystone(cx, cy, R, r, theta, out=6, inn=6):
    a, b = pt(cx, cy, R + out, 90 + theta), pt(cx, cy, R + out, 90 - theta)
    c, d = pt(cx, cy, r - inn, 90 - theta), pt(cx, cy, r - inn, 90 + theta)
    return f"M {f(a)} L {f(b)} L {f(c)} L {f(d)} Z"

def wedge(cx, cy, R, r, a0, a1):
    o0, o1 = pt(cx, cy, R, a0), pt(cx, cy, R, a1)
    i1, i0 = pt(cx, cy, r, a1), pt(cx, cy, r, a0)
    return f"M {f(o0)} A {R} {R} 0 0 1 {f(o1)} L {f(i1)} A {r} {r} 0 0 0 {f(i0)} Z"

def tile(bg, content, extra=""):
    return (f'<svg viewBox="0 0 200 200" style="width: 100%; height: 100%; display: block">'
            f'<rect width="200" height="200" rx="44" fill="{bg}"/>{extra}{content}</svg>')

INK, KEY, LIGHT = "#22252B", "#D9622F", "#F4F4F6"
soft = 'stroke-linejoin="round"'

designs = []

# 1 Capstone, redrawn clean
L, Rh = arch_halves(100, 104, 62, 34, 15, 3.5, 148)
designs.append(("Capstone", "Your idea, drawn as one clean piece per side.", "The baseline everything else is measured against.",
    tile(LIGHT, f'<path d="{L}" fill="{INK}"/><path d="{Rh}" fill="{INK}"/>'
                f'<path d="{keystone(100, 104, 62, 34, 15)}" fill="{KEY}" stroke="{KEY}" stroke-width="2" {soft}/>'
                f'<rect x="36" y="156" width="128" height="10" rx="5" fill="{INK}"/>')))

# 2 Voussoirs: the arch as individual stones
stones = []
edges = [180, 154, 129, 108.5]
for i in range(len(edges) - 1):
    start = edges[i] - (1.8 if i else 0)
    end = edges[i + 1] + 1.8
    stones.append(wedge(100, 104, 62, 34, start, end))
    stones.append(wedge(100, 104, 62, 34, 180 - end, 180 - start))
legs = ('<rect x="38" y="107" width="28" height="18" rx="2" fill="{c}"/><rect x="38" y="128" width="28" height="20" rx="2" fill="{c}"/>'
        '<rect x="134" y="107" width="28" height="18" rx="2" fill="{c}"/><rect x="134" y="128" width="28" height="20" rx="2" fill="{c}"/>').format(c=INK)
designs.append(("Voussoirs", "Every stone drawn. Reads as crafted, built.", "Too many joints to survive 16px.",
    tile("#EFE9DF", "".join(f'<path d="{s}" fill="{INK}"/>' for s in stones) + legs
         + f'<path d="{keystone(100, 104, 62, 34, 17, 7, 7)}" fill="{KEY}"/>'
         + f'<rect x="34" y="156" width="132" height="10" rx="3" fill="{INK}"/>')))

# 3 Monoline
mid, w = 48, 18
ga = 31
lo = pt(100, 104, mid, 90 + ga)
ro = pt(100, 104, mid, 90 - ga)
designs.append(("Monoline", "The arch as a single drawn line.", "Lighter; thins out at small sizes.",
    tile(LIGHT, f'<path d="M 52 146 L 52 104 A {mid} {mid} 0 0 1 {f(lo)}" fill="none" stroke="{INK}" stroke-width="{w}" stroke-linecap="round"/>'
                f'<path d="M 148 146 L 148 104 A {mid} {mid} 0 0 0 {f(ro)}" fill="none" stroke="{INK}" stroke-width="{w}" stroke-linecap="round"/>'
                f'<path d="{keystone(100, 104, 57, 39, 16, 5, 5)}" fill="{KEY}" stroke="{KEY}" stroke-width="3" {soft}/>')))

# 4 Portal: light passing through the arch
L, Rh = arch_halves(100, 104, 62, 34, 15, 3.5, 148)
designs.append(("Portal", "The opening glows. Something waits behind it.", "Reads a little like a doorway app.",
    tile("#17191E", f'<path d="M 66 148 L 66 104 A 34 34 0 0 1 134 104 L 134 148 Z" fill="#F4B266"/>'
                    f'<path d="M 66 148 L 66 104 A 34 34 0 0 1 134 104 L 134 148 Z" fill="#FFE2B0" opacity="0.55" transform="translate(100 148) scale(0.62 0.8) translate(-100 -148)"/>'
                    f'<path d="{L}" fill="#EDEAE3"/><path d="{Rh}" fill="#EDEAE3"/>'
                    f'<path d="{keystone(100, 104, 62, 34, 15)}" fill="#F07A38"/>'
                    f'<rect x="36" y="156" width="128" height="10" rx="5" fill="#EDEAE3"/>')))

# 5 Hanging: keystone pinned to the top edge, where the notch lives
L, Rh = arch_halves(100, 70, 58, 30, 15, 3.5, 150)
designs.append(("Hanging", "The keystone sits where the notch actually is.", "Top-heavy on purpose; cropped at the edge.",
    tile(LIGHT, f'<path d="{L}" fill="{INK}"/><path d="{Rh}" fill="{INK}"/>'
                f'<path d="{keystone(100, 70, 58, 30, 15, 16, 6)}" fill="{KEY}"/>'
                f'<rect x="38" y="160" width="124" height="10" rx="5" fill="{INK}"/>')))

# 6 Lowercase n
nL, nR = arch_halves(100, 96, 56, 28, 15, 3.5, 152)
designs.append(("Letter n", "The arch doubles as the n in notch.", "More wordmark than symbol.",
    tile("#FFFFFF", f'<path d="M 47 47.5 L 72 47.5 L 72 152 L 47 152 Q 44 152 44 149 L 44 50.5 Q 44 47.5 47 47.5 Z" fill="{INK}"/>'
                    f'<path d="{nL}" fill="{INK}"/><path d="{nR}" fill="{INK}"/>'
                    f'<path d="{keystone(100, 96, 56, 28, 15)}" fill="{KEY}"/>')))

# 7 Aqueduct: three arches, one keystone — many widgets, one hub
parts = ['<rect x="22" y="70" width="156" height="14" rx="3" fill="{c}"/>'.format(c=INK)]
for cx in (48, 100, 152):
    lit = cx == 100
    a, b = arch_halves(cx, 110, 26, 13, 17, 2.4 if lit else 0, 150, foot=0)
    parts.append(f'<path d="{a}" fill="{INK}"/><path d="{b}" fill="{INK}"/>')
    if lit:
        parts.append(f'<path d="{keystone(cx, 110, 26, 13, 17, 0, 4)}" fill="{KEY}"/>')
    else:
        parts.append(f'<path d="{keystone(cx, 110, 26, 13, 18, 0, 0)}" fill="{INK}"/>')
parts.append(f'<rect x="22" y="152" width="156" height="12" rx="3" fill="{INK}"/>')
designs.append(("Aqueduct", "Three arches, one lit keystone. Many tools, one hub.", "Busiest of the set.",
    tile("#EEF0F2", "".join(parts))))

# 8 Soft: friendly, round-capped, pill keystone
lo = pt(100, 106, 48, 90 + 43)
ro = pt(100, 106, 48, 90 - 43)
designs.append(("Soft", "Rounded and warm. Friendly rather than architectural.", "Loses the stone metaphor.",
    tile("#F6EFE3", f'<path d="M 52 150 L 52 106 A 48 48 0 0 1 {f(lo)}" fill="none" stroke="#1F4A4A" stroke-width="26" stroke-linecap="round"/>'
                    f'<path d="M 148 150 L 148 106 A 48 48 0 0 0 {f(ro)}" fill="none" stroke="#1F4A4A" stroke-width="26" stroke-linecap="round"/>'
                    f'<rect x="83" y="45" width="34" height="26" rx="13" fill="{KEY}"/>')))

# 9 Brass and navy
L, Rh = arch_halves(100, 104, 62, 36, 14, 3.5, 148)
designs.append(("Brass", "Navy, bone and brass. Quiet, premium.", "Lower contrast at a glance.",
    tile("#13203A", f'<path d="{L}" fill="#EDE6D6"/><path d="{Rh}" fill="#EDE6D6"/>'
                    f'<path d="{keystone(100, 104, 62, 36, 14)}" fill="#C9A15A"/>'
                    f'<rect x="40" y="158" width="120" height="6" rx="3" fill="#C9A15A"/>')))

def card(name, why, tradeoff, art):
    return f"""
    <div style="display: flex; flex-direction: column; gap: 10px">
      <div style="width: 100%; aspect-ratio: 1; border-radius: 40px; overflow: hidden">{art}</div>
      <div style="font-size: 15px; font-weight: 500">{name}</div>
      <div style="font-size: 12px; color: #9a978f; line-height: 1.5">{why}<br><span style="color: #6f6d68">{tradeoff}</span></div>
    </div>"""

reference = """
    <div style="display: flex; flex-direction: column; gap: 10px">
      <div style="width: 100%; aspect-ratio: 1; border-radius: 40px; overflow: hidden; background: #1a1a1d; display: flex; align-items: center; justify-content: center">
        <img src="original-capstone.png" style="width: 100%; height: 100%; object-fit: cover">
      </div>
      <div style="font-size: 15px; font-weight: 500">Your original</div>
      <div style="font-size: 12px; color: #9a978f; line-height: 1.5">For reference.<br><span style="color: #6f6d68">Everything here keeps its idea.</span></div>
    </div>"""

head = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;700&display=swap">
  <style>
    body { margin: 0; font-family: 'Space Grotesk', system-ui, sans-serif; }
    a { color: #d9622f; } a:hover { color: #ec7a42; }
  </style>
</helmet>"""
tail = """</x-dc>
<script data-dc-script data-props='{"$preview":{"width":%d,"height":%d}}'>
class Component extends DCLogic {
  renderVals() { return {}; }
}
</script>
</body>
</html>
"""

main = head + f"""
<div style="padding: 48px 44px 56px; background: #0e0e10; color: #f2f0eb; width: 1180px; box-sizing: border-box">
  <div style="display: flex; flex-direction: column; gap: 6px; margin-bottom: 34px">
    <div style="font-size: 30px; font-weight: 700; letter-spacing: -0.02em">The Capstone, nine ways</div>
    <div style="font-size: 15px; color: #9a978f">Same idea throughout: the keystone at top-centre that holds the arch up.</div>
  </div>
  <div style="display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 30px 22px">
    {reference}
    {"".join(card(*d) for d in designs)}
  </div>
</div>
""" + tail % (1180, 820)

rows = []
for name, _, _, art in designs:
    swatches = "".join(
        f'<div style="width: {s}px; height: {s}px; flex-shrink: 0">{art}</div>' for s in (64, 32, 16)
    )
    rows.append(f"""
    <div style="display: flex; align-items: center; gap: 22px">
      <div style="width: 96px; font-size: 13px; color: #9a978f">{name}</div>
      <div style="display: flex; align-items: center; gap: 18px; padding: 10px 16px; border-radius: 12px; background: #e9e9ec">{swatches}</div>
      <div style="display: flex; align-items: center; gap: 18px; padding: 10px 16px; border-radius: 12px; background: #1e1f23">{swatches}</div>
    </div>""")

sizes = head + f"""
<div style="padding: 44px; background: #0e0e10; color: #f2f0eb; width: 760px; box-sizing: border-box">
  <div style="display: flex; flex-direction: column; gap: 6px; margin-bottom: 28px">
    <div style="font-size: 26px; font-weight: 700; letter-spacing: -0.02em">At Dock and menu-bar size</div>
    <div style="font-size: 14px; color: #9a978f">64, 32 and 16px, on light and dark. The 16 is the one that decides.</div>
  </div>
  <div style="display: flex; flex-direction: column; gap: 14px">{"".join(rows)}</div>
</div>
""" + tail % (760, 900)

open("Capstone.dc.html", "w").write(main)
open("CapstoneSizes.dc.html", "w").write(sizes)
print("wrote", len(designs), "designs")
