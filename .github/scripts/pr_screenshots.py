#!/usr/bin/env python3
"""Takes the screenshots a pull request asks for in its description, and nothing else.

A pull request that wants screenshots of its feature lists them in a fenced block in its description:

    ```ci-screenshots
    1-budgets: -demoData varied
    2-new-expense: open dimeapp://newExpense
    ```

Each line is `name: launch arguments`. The app is relaunched with those arguments for every shot.
`open <url>` launches the app, then opens the link. Lines starting with # are ignored.

The list lives only in the description, so it goes away with the pull request: nothing has to be
reverted after testing, and later runs never take another feature's screenshots. Launch arguments
that a feature adds only for its screenshots should be removed before merging, too.

Usage: pr_screenshots.py <path to .app> <output folder>
Needs PR_BODY, SIM_UDID and BUNDLE_ID in the environment. Arguments are passed straight to simctl,
never through a shell.
"""

import glob
import os
import re
import shlex
import subprocess
import sys
import time

LAUNCH_WAIT = 8  # seconds for the app to settle before a screenshot
LINK_WAIT = 4


def simctl(*args, check=True):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, check=check)


def snap(udid, path):
    """Newer simulators list more than one display, and only one shows the app: keep the largest image."""
    result = simctl("io", udid, "screenshot", path, check=False)
    if result.returncode == 0:
        return

    best = None
    for display in re.findall(r"--display=(\d+)", result.stderr + result.stdout):
        candidate = f"{path[:-4]}-display{display}.png"
        if simctl("io", udid, "screenshot", f"--display={display}", candidate, check=False).returncode == 0:
            if best is None or os.path.getsize(candidate) > os.path.getsize(best):
                best = candidate

    for leftover in glob.glob(f"{path[:-4]}-display*.png"):
        if leftover != best:
            os.remove(leftover)
    if best:
        os.replace(best, path)


def requested_shots(body):
    match = re.search(r"```ci-screenshots[ \t]*\r?\n(.*?)```", body, re.S)
    if not match:
        return []

    shots = []
    for line in match.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _, rest = line.partition(":")
        name = re.sub(r"[^A-Za-z0-9._-]", "-", name.strip()) or f"shot-{len(shots) + 1}"
        shots.append((name, shlex.split(rest)))
    return shots


def main():
    app, out = sys.argv[1], sys.argv[2]
    udid, bundle = os.environ["SIM_UDID"], os.environ["BUNDLE_ID"]

    shots = requested_shots(os.environ.get("PR_BODY", ""))
    if not shots:
        print("The pull request asks for no screenshots.")
        return

    os.makedirs(out, exist_ok=True)
    simctl("bootstatus", udid, "-b")
    simctl("install", udid, app)

    for name, args in shots:
        simctl("terminate", udid, bundle, check=False)

        if args[:1] == ["open"] and len(args) > 1:
            simctl("launch", udid, bundle)
            time.sleep(LINK_WAIT)
            simctl("openurl", udid, args[1], check=False)
        else:
            simctl("launch", udid, bundle, *args)

        time.sleep(LAUNCH_WAIT)
        snap(udid, os.path.join(out, f"{name}.png"))
        print(f"Took {name}")


if __name__ == "__main__":
    main()
