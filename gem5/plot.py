"""Create a reproducible vector chart from validated gem5 measurements."""
import csv
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
is_conv = source.stem.startswith("conv_")
workload_label = ("13×15×64 · 5×3×64×16 INT8 Convolution" if is_conv
                  else "8-Byte-SDP-ReLU")
with source.open(newline="") as file:
    rows = list(csv.DictReader(file))
latencies = sorted({int(row["latency_ns"]) for row in rows})
if not latencies:
    raise SystemExit("no validated gem5 results")
max_cycles = max(int(row["rtl_cycles"]) for row in rows)
width, height = 900, 540
left, right, top, bottom = 100, 45, 95, 90
plot_h = height - top - bottom
plot_w = width - left - right
colors = {"loose": "#2563eb", "tight": "#e05b3f"}
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">',
       '<style>text{font-family:DejaVu Sans,Arial,sans-serif;fill:#172238}'
       '.title{font-size:24px;font-weight:700}.sub{font-size:13px;fill:#65748b}'
       '.label{font-size:14px}.tick{font-size:12px;fill:#65748b}'
       '.value{font-size:12px;font-weight:700}</style>',
       f'<rect width="{width}" height="{height}" fill="#fbfcfe"/>',
       '<text x="100" y="42" class="title">NVDLA: Loose vs. Tight</text>',
       f'<text x="100" y="65" class="sub">{workload_label} · RTL-CVA6-Zyklen · gem5/AXIOM</text>']
axis_max = max(100, ((max_cycles + 99) // 100) * 100)
for step in range(5):
    value = axis_max * step / 4
    y = top + plot_h * (1 - step / 4)
    svg += [f'<line x1="{left}" y1="{y:.1f}" x2="{width-right}" y2="{y:.1f}" stroke="#dce3ec"/>',
            f'<text x="{left-12}" y="{y+4:.1f}" text-anchor="end" class="tick">{value:,.0f}</text>']
lookup = {(row["mode"], int(row["latency_ns"])): int(row["rtl_cycles"])
          for row in rows}
group_w = plot_w / len(latencies)
bar_w = min(60, group_w * 0.28)
for index, latency in enumerate(latencies):
    center = left + group_w * (index + .5)
    for mode, offset in (("loose", -0.55), ("tight", 0.55)):
        if (mode, latency) not in lookup:
            continue
        value = lookup[(mode, latency)]
        bh = plot_h * value / axis_max
        x = center + offset * bar_w - bar_w / 2
        y = top + plot_h - bh
        svg += [f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_w:.1f}" height="{bh:.1f}" rx="5" fill="{colors[mode]}"/>',
                f'<text x="{x+bar_w/2:.1f}" y="{y-8:.1f}" text-anchor="middle" class="value">{value:,}</text>']
    svg.append(f'<text x="{center:.1f}" y="{height-bottom+28}" text-anchor="middle" class="label">{latency} ns</text>')
svg += [f'<text x="{left+plot_w/2:.1f}" y="{height-27}" text-anchor="middle" class="sub">gem5 SimpleMemory latency</text>',
        '<rect x="650" y="29" width="14" height="14" rx="3" fill="#2563eb"/>',
        '<text x="671" y="41" class="label">Loose</text>',
        '<rect x="750" y="29" width="14" height="14" rx="3" fill="#e05b3f"/>',
        '<text x="771" y="41" class="label">Tight</text>',
        '</svg>']
target.write_text("\n".join(svg))
print(target)

speedups = [(latency, lookup[("loose", latency)] / lookup[("tight", latency)])
            for latency in latencies
            if ("loose", latency) in lookup and ("tight", latency) in lookup]
if speedups:
    speedup_target = target.with_name("conv_speedup.svg" if is_conv else "speedup.svg")
    y_min = min(1.0, min(value for _, value in speedups) * .99) if is_conv else 0.0
    y_max = (max(1.01, max(value for _, value in speedups) * 1.01) if is_conv
             else max(2.0, max(value for _, value in speedups) * 1.15))
    chart = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">',
             '<style>text{font-family:DejaVu Sans,Arial,sans-serif;fill:#172238}'
             '.title{font-size:24px;font-weight:700}.sub{font-size:13px;fill:#65748b}'
             '.label{font-size:14px}.value{font-size:15px;font-weight:700}</style>',
             f'<rect width="{width}" height="{height}" fill="#fbfcfe"/>',
             '<text x="100" y="42" class="title">Vorteil des CV-X-IF-Pfads</text>',
             f'<text x="100" y="65" class="sub">Loose-Zyklen / Tight-Zyklen · {workload_label}</text>']
    levels = ([y_min + (y_max-y_min)*step/4 for step in range(5)] if is_conv
              else (1, 1.5, 2, 2.5, 3))
    for level in levels:
        y = top + plot_h * (1 - (level-y_min) / (y_max-y_min))
        if y < top:
            continue
        chart += [f'<line x1="{left}" y1="{y:.1f}" x2="{width-right}" y2="{y:.1f}" stroke="#dce3ec"/>',
                  f'<text x="{left-12}" y="{y+4:.1f}" text-anchor="end" class="sub">{level:.3f}×</text>' if is_conv else
                  f'<text x="{left-12}" y="{y+4:.1f}" text-anchor="end" class="sub">{level:.1f}×</text>']
    points = [(left + plot_w * (i + .5) / len(latencies),
               top + plot_h * (1 - (value-y_min) / (y_max-y_min)), latency, value)
              for i, (latency, value) in enumerate(speedups)]
    chart.append('<polyline points="' + ' '.join(f'{x:.1f},{y:.1f}' for x, y, _, _ in points)
                 + '" fill="none" stroke="#e05b3f" stroke-width="4" stroke-linejoin="round"/>')
    for x, y, latency, value in points:
        chart += [f'<circle cx="{x:.1f}" cy="{y:.1f}" r="8" fill="#e05b3f" stroke="white" stroke-width="3"/>',
                  f'<text x="{x:.1f}" y="{y-18:.1f}" text-anchor="middle" class="value">{value:.3f}×</text>' if is_conv else
                  f'<text x="{x:.1f}" y="{y-18:.1f}" text-anchor="middle" class="value">{value:.2f}×</text>',
                  f'<text x="{x:.1f}" y="{height-bottom+28}" text-anchor="middle" class="label">{latency} ns</text>']
    chart += [f'<text x="{left+plot_w/2:.1f}" y="{height-27}" text-anchor="middle" class="sub">gem5 SimpleMemory latency</text>',
              '</svg>']
    speedup_target.write_text("\n".join(chart))
    print(speedup_target)
