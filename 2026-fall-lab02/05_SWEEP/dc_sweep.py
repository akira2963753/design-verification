#!/usr/bin/env python3
"""DC clock-period sweep + VCS latency measurement for Lab02 LDPC.

Run on the server from 05_SWEEP (tools are launched through tcsh for license):
    python3 dc_sweep.py --rtl ../01_RTL/LDPC.v --tag v2
    python3 dc_sweep.py --rtl ../01_RTL/LDPC.v --tag v5 --cycles 3.6:4.6:0.2 --jobs 3
    python3 dc_sweep.py --report-only [--merge other/results.json ...]
    (--work / --out move run directories and results elsewhere, e.g. /tmp when /home is full)

Flow per tag:
    1. VCS  : make vcs_rtl (00_TESTBED/makefile) -> pass / total latency / max latency
    2. DC   : make syn (DC_shell overridden to dc_shell) for every clock period,
              each run in its own directory with a copy of 02_SYN/syn.tcl (CYCLE replaced)
    3. Parse Report/LDPC.area, Report/LDPC.timing, syn.log -> area, slack, error, latch
    4. Cost = Area^2 x Cycle x Latency, results kept in results.json -> DC_SWEEP.md
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJ = HERE.parent
TB_DIR = PROJ / "00_TESTBED"
SYN_DIR = PROJ / "02_SYN"
MAKEFILE = TB_DIR / "makefile"
WORK = HERE / "work"                 # --work overrides (e.g. /tmp when /home is full)
RESULTS = HERE / "results.json"      # --out overrides the directory of results.json / DC_SWEEP.md
REPORT = HERE / "DC_SWEEP.md"
DC_TEMP = ["alib-*", "*.svf", "*.pvl", "*.syn", "*.mr", "command.log"]

DEFAULT_DC = "dc_shell -f syn.tcl -x 'set_host_options -max_cores 4' -output_log_file syn.log"
DEFAULT_VERDI = "/usr/cad/synopsys/verdi/2022.06/"
LICENSE_PAT = re.compile(r"(?i)(license).*(checkout|not available|unavailable|failed)")


def log(msg):
    print(time.strftime("[%H:%M:%S] ") + msg, flush=True)


def run_tool(cmd, cwd, out_file):
    """Run a tool command inside tcsh (license environment), stdout/stderr -> out_file."""
    with open(str(out_file), "w") as f:
        p = subprocess.run(["tcsh", "-c", cmd], cwd=str(cwd), stdout=f, stderr=subprocess.STDOUT)
    return p.returncode


def read(path):
    p = Path(path)
    return p.read_text(errors="ignore") if p.exists() else ""


def parse_cycles(spec):
    lo, hi, step = (float(x) for x in spec.split(":"))
    vals, i = [], 0
    while lo + i * step <= hi + 1e-9:
        vals.append(round(lo + i * step, 2))
        i += 1
    return vals


def fmt_cyc(c):
    """Clock period label: 4.0, 4.5, 3.75 (second decimal only when needed)."""
    s = "{:.2f}".format(float(c))
    return s[:-1] if s.endswith("0") else s


# ------------------------------------------------------------------ VCS
def run_vcs(tag, rtl, verdi, keep):
    base = WORK / tag
    sim = base / "sim"
    if sim.exists():
        shutil.rmtree(str(sim))
    sim.mkdir(parents=True)
    # PATTERN opens ../00_TESTBED/input.txt relative to the run directory
    link = base / "00_TESTBED"
    if not link.exists():
        link.symlink_to(TB_DIR)
    shutil.copy(str(rtl), str(sim / "LDPC.v"))
    (sim / "filelist.f").write_text("+incdir+{0}\n+incdir+.\n{0}/TESTBED.v\n".format(TB_DIR))
    t0 = time.time()
    run_tool("make -f {} vcs_rtl VERDI={}".format(MAKEFILE, verdi), sim, sim / "run.out")
    txt = read(sim / "vcs.log")
    lats = [int(x) for x in re.findall(r"execution latency\s*:\s*(\d+)", txt)]
    m = re.search(r"Total lentency\s*:\s*(\d+)", txt)
    res = {
        "pass": "passed all patterns" in txt,
        "npat": len(lats),
        "lat_total": int(m.group(1)) if m else None,
        "lat_max": max(lats) if lats else None,
        "fail_msg": "; ".join(sorted(set(re.findall(r"Fail![^\n]*", txt))))[:200],
        "vcs_sec": round(time.time() - t0),
    }
    if res["lat_total"] and res["npat"]:
        res["lat_avg"] = res["lat_total"] / res["npat"]
    if not keep:
        for f in list(sim.glob("*.fsdb")) + [sim / "csrc", sim / "simv.daidir"]:
            if f.exists():
                shutil.rmtree(str(f)) if f.is_dir() else f.unlink()
    return res


# ------------------------------------------------------------------- DC
def prepare_syn_dir(d, rtl, cyc):
    if d.exists():
        shutil.rmtree(str(d))
    (d / "Netlist").mkdir(parents=True)
    (d / "Report").mkdir()
    src = read(SYN_DIR / "syn.tcl").replace("\r\n", "\n")
    new, n = re.subn(r"(?m)^(\s*set\s+CYCLE\s+)[0-9.]+", r"\g<1>{}".format(cyc), src)
    if n != 1:
        raise RuntimeError("syn.tcl: expected exactly one 'set CYCLE <value>' line, found {}".format(n))
    (d / "syn.tcl").write_text(new)
    setup = SYN_DIR / ".synopsys_dc.setup"
    if not setup.exists():
        setup = SYN_DIR / "synopsys_dc.setup"
    shutil.copy(str(setup), str(d / ".synopsys_dc.setup"))
    shutil.copy(str(rtl), str(d / "LDPC.v"))


def parse_syn(d):
    area_txt = read(d / "Report" / "LDPC.area")
    tim_txt = read(d / "Report" / "LDPC.timing")
    syn_log = read(d / "syn.log")

    def num(pat, txt):
        m = re.search(pat, txt)
        return float(m.group(1)) if m else None

    slack = re.search(r"slack \((MET|VIOLATED)[^)]*\)\s+(-?[\d.]+)", tim_txt)
    return {
        "area": num(r"Total cell area:\s*([\d.]+)", area_txt),
        "comb": num(r"Combinational area:\s*([\d.]+)", area_txt),
        "noncomb": num(r"Noncombinational area:\s*([\d.]+)", area_txt),
        "slack": float(slack.group(2)) if slack else None,
        "met": bool(slack) and slack.group(1) == "MET",
        "errors": len(re.findall(r"(?m)^Error", syn_log)),
        "latch": len(re.findall(r"\|\s*Latch\s*\|", syn_log)),
    }


def run_dc(tag, rtl, cyc, dc_cmd, retries):
    d = WORK / tag / "syn_T{}".format(fmt_cyc(cyc))
    prepare_syn_dir(d, rtl, cyc)
    cmd = "make -f {} syn \"DC_shell={}\"".format(MAKEFILE, dc_cmd)
    t0 = time.time()
    for attempt in range(retries + 1):
        run_tool(cmd, d, d / "run.out")
        if not LICENSE_PAT.search(read(d / "run.out") + read(d / "syn.log")[:20000]):
            break
        log("  T={}: license busy, retry {} in 60 s".format(fmt_cyc(cyc), attempt + 1))
        time.sleep(60)
    res = parse_syn(d)
    res["dc_sec"] = round(time.time() - t0)
    for pat in DC_TEMP:                              # keep Report / Netlist / logs only
        for p in d.glob(pat):
            shutil.rmtree(str(p)) if p.is_dir() else p.unlink()
    log("  T={}: area={} slack={} err={} latch={} ({} s)".format(
        fmt_cyc(cyc), res["area"], res["slack"], res["errors"], res["latch"], res["dc_sec"]))
    return cyc, res


# --------------------------------------------------------------- report
def fmt_cost(x):
    return "{:.3E}".format(x) if x else "-"


def write_report(db):
    lines = [
        "# LDPC Lab02 — DC Clock Sweep",
        "",
        "Cost = Area² × Execution time，Execution time = Cycle × Latency",
        "",
        "- **Latency (total)**：PATTERN 印出的 `Total latency` (所有 pattern 加總)",
        "- **Latency (avg)**：total / pattern 數；兩種 cost 只差固定倍數，排序完全相同",
        "- **有效** = VCS 全部 pass、slack MET、0 error、0 latch、單筆 latency ≤ 100",
        "- 產生方式：`python3 dc_sweep.py --rtl <LDPC.v> --tag <tag>`",
        "",
    ]
    best_rows = []
    for tag in sorted(db, key=lambda t: db[t].get("time", "")):
        ent = db[tag]
        v = ent.get("vcs", {})
        lat_t, lat_a = v.get("lat_total"), v.get("lat_avg")
        lines += [
            "## {}".format(tag),
            "",
            "- RTL：`{}`，時間：{}".format(ent.get("rtl", "?"), ent.get("time", "?")),
            "- VCS：{}，pattern {}，total latency {}，avg {}，max {}{}".format(
                "PASS" if v.get("pass") else "FAIL", v.get("npat"), lat_t,
                "{:.2f}".format(lat_a) if lat_a else "-", v.get("lat_max"),
                "" if v.get("pass") else "，" + v.get("fail_msg", "")),
            "",
            "| Cycle (ns) | Area (µm²) | Latency (total / avg) | Slack (ns) | Cost (total latency) | Cost (avg latency) | 狀態 |",
            "|---|---|---|---|---|---|---|",
        ]
        best = None
        for cyc_s in sorted(ent.get("dc", {}), key=float):
            r = ent["dc"][cyc_s]
            cyc = float(cyc_s)
            ok = (v.get("pass") and r.get("met") and r.get("area") and r.get("errors") == 0
                  and r.get("latch") == 0 and (v.get("lat_max") or 999) <= 100)
            c_t = r["area"] ** 2 * cyc * lat_t if (r.get("area") and lat_t) else None
            c_a = r["area"] ** 2 * cyc * lat_a if (r.get("area") and lat_a) else None
            r["cost_total"], r["cost_avg"], r["valid"] = c_t, c_a, bool(ok)
            if ok and (best is None or c_t < best[1]["cost_total"]):
                best = (cyc, r)
            status = "有效" if ok else "無效 ({})".format(
                "slack" if not r.get("met") else "error/latch" if (r.get("errors") or r.get("latch")) else "VCS")
            lines.append("| {} | {} | {} / {} | {} | {} | {} | {} |".format(
                fmt_cyc(cyc), "{:,.0f}".format(r["area"]) if r.get("area") else "-",
                lat_t if lat_t else "-", "{:.2f}".format(lat_a) if lat_a else "-",
                "{:.2f}".format(r["slack"]) if r.get("slack") is not None else "-",
                fmt_cost(c_t), fmt_cost(c_a), status))
        if best:
            lines += ["", "**最佳**：Cycle {} ns，Area {:,.0f}，Cost {} (total) / {} (avg)".format(
                fmt_cyc(best[0]), best[1]["area"], fmt_cost(best[1]["cost_total"]), fmt_cost(best[1]["cost_avg"]))]
            best_rows.append((tag, best))
        lines.append("")
    if best_rows:
        lines += ["## 各版本最佳", "",
                  "| Tag | Cycle (ns) | Area (µm²) | Latency (total) | Cost (total latency) | Cost (avg latency) |",
                  "|---|---|---|---|---|---|"]
        for tag, (cyc, r) in sorted(best_rows, key=lambda x: x[1][1]["cost_total"]):
            lines.append("| {} | {} | {:,.0f} | {} | {} | {} |".format(
                tag, fmt_cyc(cyc), r["area"], db[tag]["vcs"]["lat_total"], fmt_cost(r["cost_total"]), fmt_cost(r["cost_avg"])))
        lines.append("")
    try:
        REPORT.write_text("\n".join(lines))
        RESULTS.write_text(json.dumps(db, indent=1))
    except OSError as e:                             # e.g. disk full: keep running, retry next time
        log("  WARNING: cannot write results ({})".format(e))


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rtl", help="RTL file under test (module LDPC)")
    ap.add_argument("--tag", help="name of this design version, e.g. v2")
    ap.add_argument("--cycles", default="3.6:4.6:0.2", help="lo:hi:step in ns, clock precision 0.1 (default 3.6:4.6:0.2)")
    ap.add_argument("--jobs", type=int, default=2, help="parallel DC runs (default 2)")
    ap.add_argument("--dc-cmd", default=DEFAULT_DC, help="replacement of makefile DC_shell")
    ap.add_argument("--verdi", default=DEFAULT_VERDI, help="VERDI path for makefile vcs_rtl")
    ap.add_argument("--retries", type=int, default=5, help="license retries per DC run")
    ap.add_argument("--skip-vcs", action="store_true", help="reuse the stored VCS result of this tag")
    ap.add_argument("--keep-fsdb", action="store_true")
    ap.add_argument("--report-only", action="store_true", help="only regenerate DC_SWEEP.md")
    ap.add_argument("--work", help="directory for run directories (default 05_SWEEP/work)")
    ap.add_argument("--out", help="directory for results.json / DC_SWEEP.md (default 05_SWEEP)")
    ap.add_argument("--merge", nargs="*", help="other results.json files to merge (use with --report-only)")
    args = ap.parse_args()

    global WORK, RESULTS, REPORT
    if args.work:
        WORK = Path(args.work).resolve()
    if args.out:
        out = Path(args.out).resolve()
        out.mkdir(parents=True, exist_ok=True)
        RESULTS, REPORT = out / "results.json", out / "DC_SWEEP.md"

    db = json.loads(RESULTS.read_text()) if RESULTS.exists() else {}
    for other in args.merge or []:                   # merge results of other runs (per tag / cycle)
        for tag, ent in json.loads(Path(other).read_text()).items():
            dst = db.setdefault(tag, {})
            for key in ("rtl", "time", "vcs"):
                if key in ent and key not in dst:
                    dst[key] = ent[key]
            dst.setdefault("dc", {}).update(ent.get("dc", {}))
    if args.report_only:
        write_report(db)
        return
    if not (args.rtl and args.tag):
        ap.error("--rtl and --tag are required")
    rtl = Path(args.rtl).resolve()
    ent = db.setdefault(args.tag, {})
    ent["rtl"] = str(rtl)
    ent["time"] = time.strftime("%Y-%m-%d %H:%M")
    ent.setdefault("dc", {})

    if not (args.skip_vcs and ent.get("vcs")):
        log("[{}] VCS RTL simulation ...".format(args.tag))
        ent["vcs"] = run_vcs(args.tag, rtl, args.verdi, args.keep_fsdb)
        log("[{}] VCS: {}".format(args.tag, ent["vcs"]))
        write_report(db)
    if not ent["vcs"].get("pass"):
        log("[{}] VCS FAIL -> DC sweep still runs, results marked invalid".format(args.tag))

    cycles = parse_cycles(args.cycles)
    log("[{}] DC sweep {} with {} job(s)".format(args.tag, cycles, args.jobs))
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = [ex.submit(run_dc, args.tag, rtl, c, args.dc_cmd, args.retries) for c in cycles]
        for f in futs:
            cyc, res = f.result()
            ent["dc"][fmt_cyc(cyc)] = res
            write_report(db)
    write_report(db)
    log("[{}] done -> {}".format(args.tag, REPORT))


if __name__ == "__main__":
    sys.exit(main())
