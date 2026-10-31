#!/usr/bin/env python3
"""Check release metadata and archive contents without launching the window manager."""

import io
import pathlib
import plistlib
import struct
import tarfile
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
expected = plistlib.loads((root / "Info.plist").read_bytes())


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
    launcher = archive.getinfo(prefix + "Resources/darniri")
    assert (launcher.external_attr >> 16) & 0o111, "Homebrew launcher is not executable"
    assert b'exec /usr/bin/open "$APP_DIR"' in archive.read(launcher)
    verify_executable(archive.read(prefix + "MacOS/Darniri"))

print("ARM64 executable, app metadata, launcher, icon, and release archives verified.")
