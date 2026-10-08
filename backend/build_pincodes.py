"""Build ``data/pincodes.json`` — every Indian PIN code -> district, state, lat, lng.

The API reads this bundled file, so it needs no runtime dependency. The file is
(re)built by ``.github/workflows/price-cache.yml``, which installs ``indiapins``
just for this step, so the mapping stays current.

Run manually with:  pip install indiapins && python build_pincodes.py
"""

import bz2
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "data" / "pincodes.json"


def main():
    try:
        import indiapins
    except ImportError:
        print("indiapins not installed - run: pip install indiapins")
        return 1

    src = Path(indiapins.__file__).parent / "pins.json.bz2"
    pins = {}
    with bz2.open(src, "rt", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            pin = str(rec.get("Pincode") or rec.get("pincode") or "").strip()
            if len(pin) != 6 or not pin.isdigit():
                continue
            if pin in pins:
                continue
            pins[pin] = [
                (rec.get("District") or "").strip().title(),
                (rec.get("State") or "").strip().title(),
                rec.get("Latitude"),
                rec.get("Longitude"),
            ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(pins, separators=(",", ":"), ensure_ascii=False))
    print(f"wrote {OUT} with {len(pins)} PIN codes ({OUT.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
