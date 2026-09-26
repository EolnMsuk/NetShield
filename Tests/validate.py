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
control_bytes = (root / "control").read_bytes()
assert b"\r" not in control_bytes, "control must use Unix LF line endings for Debian packaging"
control = control_bytes.decode("utf-8")
assert "Architecture: iphoneos-arm64" in control
assert "rocketbootstrap" not in control.lower()
loader = plistlib.loads((root / "layout/Library/PreferenceLoader/Preferences/com.eolnmsuk.netshield.plist").read_bytes())
assert loader["entry"]["bundle"] == "NetShieldPrefs"
assert (root / "Preferences/Resources/Info.plist").is_file()
assert not list((root / "layout").glob("var/jb/**")), "Theos adds the rootless prefix"
print(f"Validated {len(plists)} plists, source paths, dependencies and rootless layout")

# Release metadata and shipped artwork must agree with the package.
metadata = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line)
info = plistlib.loads((root / "Preferences/Resources/Info.plist").read_bytes())
assert metadata["Package"] == "com.eolnmsuk.netshield"
assert "/var/mobile/Library/Preferences/com.eolnmsuk.netshield.plist" in (root / "Sources/Shared.h").read_text()
assert metadata["Version"] == info["CFBundleShortVersionString"] == "1.0.0"
assert metadata["Author"] == metadata["Maintainer"] == "EolnMsuk"
assert metadata["Homepage"] == "https://github.com/EolnMsuk/NetShield"
assert loader["entry"]["icon"] == "NetShield.png"
assert "Tests/Probe" not in make
assert "BUILD_PROBE" not in (root / ".github/workflows/build.yml").read_text()
assert "netshield-probe" not in (root / "NetShield.plist").read_text()
for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
    for relative in (f"Preferences/Resources/icon{suffix}.png",
                     f"layout/Library/PreferenceLoader/Preferences/NetShield{suffix}.png"):
        png = (root / relative).read_bytes()
        assert png[:8] == b"\x89PNG\r\n\x1a\n", relative
        assert int.from_bytes(png[16:20], "big") == 29 * scale, relative
        assert int.from_bytes(png[20:24], "big") == 29 * scale, relative
for name in ("icon.png", "banner.png"):
    assert (root / "assets" / name).is_file()
print("Validated 1.0.0 release metadata, icon variants and probe exclusion")
