"""Run one AXIOM/gem5 experiment and keep only validated measurements."""
import argparse
import csv
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--gem5", type=Path, required=True)
parser.add_argument("--mode", choices=("loose", "tight"), required=True)
parser.add_argument("--latency", required=True)
parser.add_argument("--workload", choices=("relu", "conv"), default="relu")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
tag = f"{args.workload}-{args.mode}-{args.latency}"
run_dir = root / "build/gem5/runs" / tag
run_dir.mkdir(parents=True, exist_ok=True)
command = [str(args.gem5), f"--outdir={run_dir}", str(root / "gem5/run.py"),
           "--driver", str(root / f"build/gem5/{'conv_driver' if args.workload == 'conv' else 'driver'}.elf"),
           "--firmware", str(root / f"build/{args.mode}/{args.workload}.elf"),
           "--plugin", str(root / f"build/gem5/{args.mode}/libnvdla_{args.mode}.so"),
           "--latency", args.latency,
           "--driver-output", str(run_dir / "driver.log")]
run = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, timeout=900)
(run_dir / "run.log").write_text(run.stdout)
driver_output = (run_dir / "driver.log").read_text() if (run_dir / "driver.log").exists() else ""
match = re.search(r"RESULT cycles=(\d+) polls=(\d+) status=PASS", driver_output)
exit_match = re.search(r"GEM5_EXIT tick=(\d+) cause=(.+)", run.stdout)
if run.returncode or not match or not exit_match or "FAIL:" in driver_output:
    raise SystemExit(f"gem5 experiment failed ({tag}); see {run_dir / 'run.log'}")
row = {"mode": args.mode, "latency_ns": int(args.latency.removesuffix("ns")),
       "rtl_cycles": int(match[1]), "driver_polls": int(match[2]),
       "gem5_ticks": int(exit_match[1])}
path = root / f"gem5/{'conv_results' if args.workload == 'conv' else 'results'}.csv"
fields = list(row)
rows = []
if path.exists():
    with path.open(newline="") as file:
        rows = [old for old in csv.DictReader(file)
                if not (old["mode"] == args.mode and
                        old["latency_ns"] == str(row["latency_ns"]))]
rows.append(row)
rows.sort(key=lambda item: (int(item["latency_ns"]), item["mode"]))
with path.open("w", newline="") as file:
    writer = csv.DictWriter(file, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
print(f"PASS {tag}: {row['rtl_cycles']} RTL cycles; log: {run_dir / 'run.log'}")
