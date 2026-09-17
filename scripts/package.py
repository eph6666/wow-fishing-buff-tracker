#!/usr/bin/env python3
"""Build reproducible install archives using the addon's TOC as the file list."""

import argparse
import gzip
import hashlib
import io
import re
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Expected TOC version, with optional v prefix")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    addon = root / "FishingBuffTracker"
    toc = addon / "FishingBuffTracker.toc"
    lines = toc.read_text(encoding="utf-8").splitlines()
    versions = [line.partition(":")[2].strip() for line in lines if line.startswith("## Version:")]
    expected = args.version.removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", expected):
        parser.error("Version must have the form 0.3.0 or 0.3.0-rc.1")
    if versions != [expected]:
        parser.error(f"Tag version {expected!r} does not match TOC version {versions!r}")

    names = [toc.name] + [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]
    if len(names) != len(set(names)):
        parser.error("The TOC contains duplicate runtime files")
    members = []
    for name in names:
        relative = PurePosixPath(name.replace("\\", "/"))
        source = addon / relative
        if relative.is_absolute() or ".." in relative.parts or source.is_symlink() or not source.is_file():
            parser.error(f"Invalid runtime file in TOC: {name}")
        members.append((str(PurePosixPath(addon.name) / relative), source.read_bytes()))

    output = root / "dist"
    output.mkdir(exist_ok=True)
    stem = f"FishingBuffTracker-v{expected}"
    zip_path = output / f"{stem}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in members:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, content, compresslevel=9)

    tar_path = output / f"{stem}.tar.gz"
    with tar_path.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                for name, content in members:
                    info = tarfile.TarInfo(name)
                    info.size = len(content)
                    info.mode = 0o644
                    info.mtime = 0
                    archive.addfile(info, io.BytesIO(content))

    checksum_lines = []
    for artifact in [zip_path, tar_path]:
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        checksum_lines.append(f"{digest}  {artifact.name}\n")
        print(f"{artifact.relative_to(root)} ({artifact.stat().st_size} bytes)")
    checksums = output / "SHA256SUMS"
    checksums.write_text("".join(checksum_lines), encoding="utf-8")
    print(checksums.relative_to(root))


if __name__ == "__main__":
    main()
