#!/usr/bin/env python3
"""Run sequential VCS random-seed regressions and summarize failures."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from collections import deque
from pathlib import Path


DEFAULT_START_SEED = 7
DEFAULT_SEED_COUNT = 200
DEFAULT_TARGET = "vcs_fast"

SUCCESS_MARKER = "OISS Environment Completed"
ERROR_PATTERN = re.compile(
    r"(?:^\s*Error(?:-\[[^]]+\])?\s*:|"
    r"^\s*Fatal(?:-\[[^]]+\])?\s*:|"
    r"Scoreboard Check Failed|"
    r"Simulation timeout|"
    r"Randomization Failed|"
    r"Mailbox is Full|"
    r"Monitor Valid is X/Z|"
    r"Segmentation fault|"
    r"core dumped|"
    r"make(?:\[\d+\])?: \*\*\*)",
    re.IGNORECASE,
)
ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def positive_integer(value: str) -> int:
    number = int(value)
    if(number <= 0):
        raise argparse.ArgumentTypeError("value must be greater than zero")
    return number


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run VCS regressions with sequential random seeds."
    )
    parser.add_argument(
        "--start",
        type=positive_integer,
        default=DEFAULT_START_SEED,
        help=f"first random seed (default: {DEFAULT_START_SEED})",
    )
    parser.add_argument(
        "--count",
        type=positive_integer,
        default=DEFAULT_SEED_COUNT,
        help=f"number of seeds to run (default: {DEFAULT_SEED_COUNT})",
    )
    parser.add_argument(
        "--target",
        choices=("vcs_fast", "vcs_rtl", "vcs_gate"),
        default=DEFAULT_TARGET,
        help=f"make target (default: {DEFAULT_TARGET})",
    )
    return parser.parse_args()


def analyze_log(log_path: Path) -> tuple[bool, list[str]]:
    if(not log_path.is_file()):
        return False, [f"Log file was not created: {log_path.name}"]

    success_found = False
    failure_details: list[str] = []
    tail: deque[str] = deque(maxlen=20)
    scoreboard_failure = False

    with log_path.open("r", encoding="utf-8", errors="replace") as log_file:
        for raw_line in log_file:
            line = ANSI_PATTERN.sub("", raw_line.rstrip())
            if(not line):
                continue

            tail.append(line)
            if(SUCCESS_MARKER in line):
                success_found = True
            if("Scoreboard Check Failed" in line):
                scoreboard_failure = True
            if(ERROR_PATTERN.search(line)):
                failure_details.append(line)
            elif(scoreboard_failure and not set(line) <= {"="}):
                failure_details.append(line)

    if(not success_found and not failure_details):
        failure_details.append(f'Missing success marker: "{SUCCESS_MARKER}"')
        failure_details.extend(tail)

    # Preserve order while removing repeated simulator messages.
    failure_details = list(dict.fromkeys(failure_details))
    passed = success_found and not failure_details
    return passed, failure_details[:40]


def run_seed(
    work_dir: Path,
    makefile: Path,
    target: str,
    seed: int,
) -> tuple[bool, list[str], float]:
    log_path = work_dir / f"seed_{seed}.log"
    if(log_path.exists()):
        log_path.unlink()

    command = [
        "make",
        "-f",
        str(makefile),
        target,
        f"seed={seed}",
    ]
    start_time = time.monotonic()
    result = subprocess.run(
        command,
        cwd=work_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    elapsed = time.monotonic() - start_time

    passed, errors = analyze_log(log_path)
    if(result.returncode != 0):
        passed = False
        errors.insert(0, f"make exited with status {result.returncode}")
        if(result.stderr.strip()):
            errors.extend(result.stderr.strip().splitlines()[-10:])

    return passed, list(dict.fromkeys(errors))[:40], elapsed


def main() -> int:
    args = parse_arguments()
    work_dir = Path(__file__).resolve().parent
    makefile = (work_dir / "../00_TESTBED/makefile").resolve()

    if(not makefile.is_file()):
        print(f"ERROR: makefile not found: {makefile}", file=sys.stderr)
        return 2

    seeds = range(args.start, args.start + args.count)
    failures: list[tuple[int, list[str]]] = []
    passed_count = 0

    print("=" * 64)
    print("Random-Seed Regression")
    print(
        f"target={args.target}, start_seed={args.start}, "
        f"seed_count={args.count}"
    )
    print("=" * 64)

    try:
        for run_index, seed in enumerate(seeds, start=1):
            print(f"[{run_index:>4}/{args.count}] seed={seed} ... ", end="", flush=True)
            passed, errors, elapsed = run_seed(
                work_dir, makefile, args.target, seed
            )
            if(passed):
                passed_count += 1
                print(f"PASS ({elapsed:.1f}s)")
            else:
                failures.append((seed, errors))
                print(f"FAIL ({elapsed:.1f}s)")
    except FileNotFoundError:
        print("\nERROR: make command was not found", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\nRegression interrupted by user", file=sys.stderr)
        return 130

    print("=" * 64)
    print(
        f"Regression completed: total={args.count}, "
        f"passed={passed_count}, failed={len(failures)}"
    )

    for seed, errors in failures:
        print("-" * 64)
        print(f"Seed {seed} failed: seed_{seed}.log")
        for error in errors:
            print(f"  {error}")

    print("=" * 64)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
