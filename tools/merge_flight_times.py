"""Copies the flights timed in game (MapzerothDataTools' Dev.lua saves every one to
MapzerothDataToolsDB.flightTimes) into tools/flight_source/flight_samples.tsv, which keeps them for good:
SavedVariables can be wiped, and the repo can't. A sample already in the file isn't added twice, so run it
as often as you like. Only Forever flights are taken. Then run gen_flights.py, which reads the file.

    python tools/merge_flight_times.py [path to MapzerothDataTools.lua]

Without a path it reads every account's SavedVariables on the Forever beta.
"""
import pathlib
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAMPLES = ROOT / "tools" / "flight_source" / "flight_samples.tsv"
WTF = pathlib.Path(r"D:\World of Warcraft\_classic_beta_\WTF\Account")

HEADER = """# Flights timed in game, lift-off to landing, one per line: written by tools/merge_flight_times.py from
# MapzerothDataTools' SavedVariables; read by tools/gen_flights.py. `seconds` is the raw time: `flier` 1 means
# the character had Frequent Flier (a faster flight), which gen_flights takes off to get the base time.
# `stops` are where the flight landed, in order, the last being where it ended (more than one: a through-ticket).
# date\tfaction\tflier\tseconds\tfrom\tstops
"""


def read_saved(path):
    lua = lupa.LuaRuntime()
    lua.execute(path.read_text(encoding="utf-8"))
    db = lua.globals().MapzerothDataToolsDB
    times = db and db["flightTimes"]
    out = []
    for i in range(1, len(times or {}) + 1):
        r = times[i]
        if r["ruleset"] != "forever":
            continue
        stops = [r["stops"][j] for j in range(1, len(r["stops"]) + 1)]
        out.append((r["date"], r["faction"], "1" if r["flier"] else "0", f"{float(r['seconds']):.1f}",
                    r["from"], ",".join(stops)))
    return out


def main():
    paths = [pathlib.Path(sys.argv[1])] if len(sys.argv) > 1 else \
        sorted(WTF.glob("*/SavedVariables/MapzerothDataTools.lua"))
    known = []
    if SAMPLES.exists():
        known = [tuple(line.split("\t")) for line in SAMPLES.read_text(encoding="utf-8").splitlines()
                 if line and not line.startswith("#")]
    seen, added = set(known), []
    for path in paths:
        for row in read_saved(path):
            if row not in seen:
                seen.add(row)
                added.append(row)
    rows = sorted(known + added)
    SAMPLES.write_text(HEADER + "".join("\t".join(r) + "\n" for r in rows), encoding="utf-8")
    print(f"read {len(paths)} SavedVariables file(s): {len(added)} new flight(s), {len(rows)} in all")
    if added:
        print("now run: python tools/gen_flights.py")


if __name__ == "__main__":
    main()
