"""Builds the enhanced Capstone icons as precise vector geometry.

The original's arch, legs and keystone are separate shapes, which leaves nicks at the
joins and hairline fringes at the keystone. Here each half of the arch is one continuous
path (arch and leg together), the keystone's sides run along true radii, and the joints
between them are a deliberate, constant width.
"""
import math

CX = 512.0

def pt(cx, cy, radius, degrees):
    a = math.radians(degrees)
    return (cx + radius * math.cos(a), cy - radius * math.sin(a))

def fmt(p):
    return f"{p[0]:.2f} {p[1]:.2f}"

def squircle(size=824, offset=100, n=5.0, samples=240):
    """Apple-style continuous-curvature tile, as a superellipse."""
    half = size / 2
    c = offset + half
    points = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        ct, st = math.cos(t), math.sin(t)
        x = c + half * math.copysign(abs(ct) ** (2 / n), ct)
        y = c + half * math.copysign(abs(st) ** (2 / n), st)
        points.append(f"{x:.2f} {y:.2f}")
    return "M " + " L ".join(points) + " Z"

def line_circle(p, d, cx, cy, radius):
    """Far intersection of the ray p + t*d with a circle."""
    fx, fy = p[0] - cx, p[1] - cy
    a = d[0] ** 2 + d[1] ** 2
    b = 2 * (fx * d[0] + fy * d[1])
    c = fx ** 2 + fy ** 2 - radius ** 2
    disc = math.sqrt(max(0.0, b * b - 4 * a * c))
    t = (-b + disc) / (2 * a)
    return (p[0] + t * d[0], p[1] + t * d[1])

def capstone(R, r, cy, leg_bottom, theta, gap, key_out, key_in,
             base_top, base_height, base_overhang, foot_radius, soften):
    """Returns (left, right, keystone, base) path strings.

    `soften` is the round-join stroke applied at render time; geometry is shrunk by half
    of it everywhere so the visible shape and gaps land exactly on the intended sizes.
    """
    s = soften / 2
    Ro, ri = R - s, r + s
    g = gap + soften

    # Keystone sides lie on radii at 90° ± theta.
    k_top_l = pt(CX, cy, R + key_out - s, 90 + theta)
    k_top_r = pt(CX, cy, R + key_out - s, 90 - theta)
    k_bot_l = pt(CX, cy, r - key_in + s, 90 + theta)
    k_bot_r = pt(CX, cy, r - key_in + s, 90 - theta)
    keystone = f"M {fmt(k_top_l)} L {fmt(k_top_r)} L {fmt(k_bot_r)} L {fmt(k_bot_l)} Z"

    def half(sign):
        # Joint line: the keystone side, pushed out by the gap along its normal.
        ang = math.radians(90 + sign * theta)
        direction = (math.cos(ang), -math.sin(ang))
        normal = (-direction[1], direction[0]) if sign > 0 else (direction[1], -direction[0])
        # Normal must point away from the keystone, i.e. toward this side.
        if (normal[0] > 0) != (sign < 0):
            normal = (-normal[0], -normal[1])
        origin = (CX + normal[0] * g, cy + normal[1] * g)
        outer = line_circle(origin, direction, CX, cy, Ro)
        inner = line_circle(origin, direction, CX, cy, ri)

        x_out = CX - sign * Ro
        x_in = CX - sign * ri
        sweep_out = 1 if sign > 0 else 0
        sweep_in = 0 if sign > 0 else 1
        fr = foot_radius
        bottom = leg_bottom - s
        return (
            f"M {x_out:.2f} {cy:.2f} "
            f"A {Ro:.2f} {Ro:.2f} 0 0 {sweep_out} {fmt(outer)} "
            f"L {fmt(inner)} "
            f"A {ri:.2f} {ri:.2f} 0 0 {sweep_in} {x_in:.2f} {cy:.2f} "
            f"L {x_in:.2f} {bottom - fr:.2f} "
            f"Q {x_in:.2f} {bottom:.2f} {x_in - sign * fr:.2f} {bottom:.2f} "
            f"L {x_out + sign * fr:.2f} {bottom:.2f} "
            f"Q {x_out:.2f} {bottom:.2f} {x_out:.2f} {bottom - fr:.2f} Z"
        )

    left = half(+1)
    right = half(-1)

    bx0 = CX - R - base_overhang + s
    bx1 = CX + R + base_overhang - s
    base = (bx0, base_top + s, bx1 - bx0, base_height - soften)
    return left, right, keystone, base

def mark(params, ink, key, soften, ink_fill=None, key_fill=None, extras=""):
    left, right, keystone, base = capstone(**params, soften=soften)
    ink_paint = ink_fill or ink
    key_paint = key_fill or key
    stroke_ink = f'stroke="{ink}" stroke-width="{soften}" stroke-linejoin="round"'
    stroke_key = f'stroke="{key}" stroke-width="{soften}" stroke-linejoin="round"'
    bx, by, bw, bh = base
    radius = max(0.0, bh / 2 - 2)
    return (
        f'<path d="{left}" fill="{ink_paint}" {stroke_ink}/>'
        f'<path d="{right}" fill="{ink_paint}" {stroke_ink}/>'
        f'<rect x="{bx:.2f}" y="{by:.2f}" width="{bw:.2f}" height="{bh:.2f}" rx="{radius:.2f}" fill="{ink_paint}" {stroke_ink}/>'
        + (f'<path d="{keystone}" fill="{key_paint}" {stroke_key}/>' if key else "")
        + extras
    )

# Faithful to the original's proportions, one notch heavier and a little larger.
REGULAR = dict(R=288, r=160, cy=522, leg_bottom=690, theta=15, gap=12, key_out=14, key_in=16,
               base_top=718, base_height=44, base_overhang=6, foot_radius=10)

# Optically sized for 16–32px: heavier band, bigger keystone, no joints to smear.
SMALL = dict(R=318, r=150, cy=520, leg_bottom=680, theta=20, gap=0, key_out=20, key_in=20,
             base_top=712, base_height=64, base_overhang=10, foot_radius=8)

INK, KEY = "#22252B", "#D9622F"
TILE = squircle()

def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>')

files = {}

files["capstone-refined.svg"] = svg(
    f'<path d="{TILE}" fill="#F4F4F6" stroke="#E2E2E7" stroke-width="2"/>'
    + mark(REGULAR, INK, KEY, soften=10)
)

files["capstone-dimensional.svg"] = svg(
    f'<path d="{TILE}" fill="url(#tile)"/>'
    f'<path d="{TILE}" fill="none" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="3"/>'
    # A soft contact shade under the base, built from layered translucent bars.
    + "".join(
        f'<rect x="{212 - i * 6}" y="{748 + i * 4}" width="{600 + i * 12}" height="26" rx="13" fill="#000" opacity="{0.035 - i * 0.008:.3f}"/>'
        for i in range(4)
    )
    + mark(REGULAR, "#262930", KEY, soften=10, ink_fill="url(#ink)", key_fill="url(#key)",
           extras='<path d="M 437 236 L 587 236" stroke="#F6A777" stroke-width="5" stroke-linecap="round" opacity="0.55"/>'),
    defs=(
        '<linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FDFDFE"/><stop offset="1" stop-color="#E9E9EE"/></linearGradient>'
        '<linearGradient id="ink" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#32363F"/><stop offset="1" stop-color="#1B1D22"/></linearGradient>'
        '<linearGradient id="key" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#EC7A42"/><stop offset="1" stop-color="#C4522A"/></linearGradient>'
    ),
)

files["capstone-dark.svg"] = svg(
    f'<path d="{TILE}" fill="#1D1F24" stroke="#2E3138" stroke-width="2"/>'
    + mark(REGULAR, "#F1EFEA", "#E46A34", soften=10)
)

files["capstone-small.svg"] = svg(
    f'<path d="{TILE}" fill="#F4F4F6" stroke="#E2E2E7" stroke-width="2"/>'
    + mark(SMALL, INK, KEY, soften=6)
)

# Menu-bar templates: no tile, black only, transparent. Scaled to fill the canvas.
TEMPLATE_SCALE = 'transform="translate(512 512) scale(1.5) translate(-512 -492)"'
files["capstone-template-keystone.svg"] = svg(
    f'<g {TEMPLATE_SCALE}>' + mark(dict(SMALL, gap=26), "#000", "#000", soften=6) + "</g>"
)
# The keystone slot left open: at 16px the arch reads as split at the top — the notch.
files["capstone-template-open.svg"] = svg(
    f'<g {TEMPLATE_SCALE}>' + mark(dict(SMALL, gap=26), "#000", None, soften=6) + "</g>"
)

for name, content in files.items():
    with open(name, "w") as handle:
        handle.write(content)
    print("wrote", name)

# ---- Icon Composer bundle: real light and dark appearances -------------------
#
# A classic .icns holds one image, so on macOS 26 the system fakes Dark mode by
# darkening the whole tile — dark arch on dark tile. An .icon bundle carries the
# background and each layer per appearance, and the system picks the right one.
import json, os

def layer_svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>'

def arch_only(ink, soften=10):
    left, right, _, base = capstone(**REGULAR, soften=soften)
    stroke = f'stroke="{ink}" stroke-width="{soften}" stroke-linejoin="round"'
    bx, by, bw, bh = base
    return (f'<path d="{left}" fill="{ink}" {stroke}/><path d="{right}" fill="{ink}" {stroke}/>'
            f'<rect x="{bx:.2f}" y="{by:.2f}" width="{bw:.2f}" height="{bh:.2f}" rx="{max(0.0, bh / 2 - 2):.2f}" fill="{ink}" {stroke}/>')

def keystone_only(color, soften=10):
    _, _, key, _ = capstone(**REGULAR, soften=soften)
    return f'<path d="{key}" fill="{color}" stroke="{color}" stroke-width="{soften}" stroke-linejoin="round"/>'

def srgb(hex_colour):
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"

bundle = "AppIcon.icon"
os.makedirs(f"{bundle}/Assets", exist_ok=True)
layers = {
    "arch-on-light.svg": layer_svg(arch_only("#22252B")),
    "arch-on-dark.svg": layer_svg(arch_only("#EEEBE4")),
    "keystone.svg": layer_svg(keystone_only("#D9622F")),
    "keystone-on-dark.svg": layer_svg(keystone_only("#E8703A")),
}
for name, content in layers.items():
    open(f"{bundle}/Assets/{name}", "w").write(content)

icon = {
    "fill-specializations": [
        {"value": {"solid": srgb("#F4F4F6")}},
        {"appearance": "dark", "value": {"solid": srgb("#2B2E35")}},
    ],
    "groups": [
        {
            "name": "Keystone",
            "layers": [{
                "name": "keystone",
                "image-name-specializations": [
                    {"value": "keystone.svg"},
                    {"appearance": "dark", "value": "keystone-on-dark.svg"},
                ],
            }],
            "shadow": {"kind": "neutral", "opacity": 0.35},
            "translucency": {"enabled": False, "value": 0},
        },
        {
            "name": "Arch",
            "layers": [{
                "name": "arch",
                "image-name-specializations": [
                    {"value": "arch-on-light.svg"},
                    {"appearance": "dark", "value": "arch-on-dark.svg"},
                ],
            }],
            "shadow": {"kind": "neutral", "opacity": 0.25},
            "translucency": {"enabled": False, "value": 0},
        },
    ],
    "supported-platforms": {"squares": "shared"},
}
json.dump(icon, open(f"{bundle}/icon.json", "w"), indent=2)
print("wrote", bundle)
