"""Dependency-free source/package sanity checks. Does not compile or emulate iOS."""
import pathlib
import plistlib
import re
from xml.parsers.expat import ExpatError

root = pathlib.Path(__file__).resolve().parents[1]
# Only validate project inputs. CI installs Theos (including SDKs and templates)
# under .theos-toolchain, whose plists are not NetShield package inputs.
plists = sorted([
    *root.glob("*.plist"),
    *(root / "Preferences").rglob("*.plist"),
    *(root / "layout").rglob("*.plist"),
])
for path in plists:
    try:
        with path.open("rb") as stream:
            plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError) as error:
        raise SystemExit(f"Invalid plist {path.relative_to(root)}: {error}") from error

make = (root / "Makefile").read_text()
for variable in ("NetShield_FILES",):
    files = re.search(rf"^{variable} = (.+)$", make, re.M).group(1).split()
    for name in files:
        assert (root / name).is_file(), f"Missing source {name}"
assert "THEOS_PACKAGE_SCHEME = rootless" in make
assert "arm64 arm64e" in make
control = (root / "control").read_text()
assert "Architecture: iphoneos-arm64" in control
assert "rocketbootstrap" not in control.lower()
loader = plistlib.loads((root / "layout/Library/PreferenceLoader/Preferences/NetShield.plist").read_bytes())
assert loader["entry"]["bundle"] == "NetShieldPrefs"
assert (root / "Preferences/Resources/Info.plist").is_file()
assert not list((root / "layout").glob("var/jb/**")), "Theos adds the rootless prefix"
print(f"Validated {len(plists)} plists, source paths, dependencies and rootless layout")
