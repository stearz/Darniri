#!/usr/bin/env python3
"""Check release metadata and archive contents without launching the window manager."""

import io
import json
import os
import pathlib
import plistlib
import struct
import subprocess
import tarfile
import tempfile
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
expected = plistlib.loads((root / "Info.plist").read_bytes())
version = (root / "VERSION").read_text().strip()
manifest = json.loads((root / ".release-please-manifest.json").read_text())
assert expected["CFBundleShortVersionString"] == version, "App version differs from VERSION"
assert expected["CFBundleVersion"] == version, "Build version differs from VERSION"
assert manifest["."] == version, "Release Please manifest differs from VERSION"


def verify_executable(binary):
    magic, cpu_type = struct.unpack_from("<II", binary)
    assert magic == 0xFEEDFACF and cpu_type == 0x0100000C, "Expected an ARM64 Mach-O executable"
    command_count = struct.unpack_from("<I", binary, 16)[0]
    cursor = 32
    for _ in range(command_count):
        command, command_size = struct.unpack_from("<II", binary, cursor)
        if command == 0x19:  # LC_SEGMENT_64
            section_count = struct.unpack_from("<I", binary, cursor + 64)[0]
            for index in range(section_count):
                section = cursor + 72 + index * 80
                name = binary[section:section + 16].rstrip(b"\0")
                if name == b"__info_plist":
                    _, size, offset = struct.unpack_from("<QQI", binary, section + 32)
                    metadata = plistlib.loads(binary[offset:offset + size].rstrip(b"\0"))
                    assert metadata == expected, "Executable version metadata differs from Info.plist"
                    return
        cursor += command_size
    raise AssertionError("Executable is missing embedded Info.plist metadata")


with tarfile.open(root / "dist/Darniri-arm64.tar.gz") as archive:
    members = archive.getmembers()
    assert [item.name for item in members] == ["Darniri"]
    assert members[0].mode & 0o111, "Standalone executable is not executable"
    verify_executable(archive.extractfile(members[0]).read())

with zipfile.ZipFile(root / "dist/Darniri-arm64.zip") as archive:
    prefix = "Darniri.app/Contents/"
    metadata = plistlib.load(io.BytesIO(archive.read(prefix + "Info.plist")))
    assert metadata == expected, "App bundle version differs from Info.plist"
    assert archive.read(prefix + "Resources/AppIcon.icns"), "Missing app icon"
    for icon in ["StatusIcon.png", "StatusIcon@2x.png"]:
        assert archive.read(prefix + "Resources/" + icon), "Missing status icon"
    launcher = archive.getinfo(prefix + "Resources/darniri")
    assert (launcher.external_attr >> 16) & 0o111, "Homebrew launcher is not executable"
    assert b'exec /usr/bin/open "$APP_DIR"' in archive.read(launcher)
    verify_executable(archive.read(prefix + "MacOS/Darniri"))

# Verify the actual archived bytes too, after extraction. PR checks opt into
# ad-hoc signing; public packaging must retain the Developer ID signature/ticket.
with tempfile.TemporaryDirectory(prefix="darniri-release-verification-") as directory:
    destination = pathlib.Path(directory)
    with tarfile.open(root / "dist/Darniri-arm64.tar.gz") as archive:
        binary = destination / "Darniri"
        binary.write_bytes(archive.extractfile("Darniri").read())
        binary.chmod(0o755)
    subprocess.run(["ditto", "-x", "-k", str(root / "dist/Darniri-arm64.zip"), directory], check=True)
    app = destination / "Darniri.app"
    signed = os.environ.get("DARNIRI_SIGNING_MODE", "developer-id") == "developer-id"
    requirement = ('identifier "io.github.stearz.darniri" and anchor apple generic and '
                   'certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
    team = os.environ.get("DARNIRI_TEAM_ID")
    if team:
        assert len(team) == 10 and team.isascii() and team.isalnum(), "Invalid developer team"
        requirement += f' and certificate leaf[subject.OU] = "{team}"'
    for target in [binary, app]:
        command = ["codesign", "--verify", "--strict"]
        if signed:
            command += ["--test-requirement", "=" + requirement]
        subprocess.run(command + [str(target)], check=True)
    if signed:
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)

print("ARM64 executable, app metadata, launcher, icons, signatures, and release archives verified.")
