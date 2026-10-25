import hashlib as HashLib
import os as OS
from pathlib import Path
import platform as Platform
import shutil as ShUtil
import subprocess as Subprocess
import tarfile as TarFile
import tempfile as TempFile
import urllib.request as Request

Root = Path(__file__).resolve().parents[1]
Destination = Root / "BuildTools/7zip"
Source = Root / "Source/ArchiveReclamation/ArchiveReclamation.hpp"
Stamp = Destination / "Reclamation.sha256"
Digest = HashLib.sha256(Source.read_bytes() + Path(__file__).read_bytes()).hexdigest()
Architectures = OS.environ.get("ASCENDARA_ARCHIVE_ARCHS", Platform.machine()).split()
Signature = Digest + " " + " ".join(Architectures)

if not (Destination / "7zz-reclaim").is_file() or not Stamp.is_file() or Stamp.read_text() != Signature:
    Destination.mkdir(parents=True, exist_ok=True)
    with TempFile.TemporaryDirectory(prefix="AscendaraArchiveBuild-") as Temporary:
        Working = Path(Temporary)
        Archive = Working / "7zip.tar.xz"
        with Request.urlopen("https://github.com/ip7z/7zip/releases/download/26.03/7z2603-src.tar.xz", timeout=60) as Response:
            Archive.write_bytes(Response.read())
        if HashLib.sha256(Archive.read_bytes()).hexdigest() != "9cbde5099c6deb73691b0579063da5827522ccbbcba3f0020fd04e8c8c16c0d4":
            raise RuntimeError("The 7-Zip source checksum did not match.")
        with TarFile.open(Archive) as Package:
            for Entry in Package.getmembers():
                if Entry.name.startswith("/") or ".." in Path(Entry.name).parts or not (Entry.isfile() or Entry.isdir()):
                    raise RuntimeError("The 7-Zip source package contains an unsafe entry.")
            Package.extractall(Working)
        FileIO = Working / "CPP/Windows/FileIO.cpp"
        FileIO.chmod(0o644)
        Text = FileIO.read_text()
        for Original, Replacement in [('#include "StdAfx.h"', '#include "StdAfx.h"\n#include "ArchiveReclamation.hpp"'),
                                      ('return ::read(_handle, data, size);', 'return ArchiveRead(_handle, data, size);'),
                                      ('return ::write(_handle, data, size);', 'return ArchiveWrite(_handle, data, size);')]:
            if Text.count(Original) != 1:
                raise RuntimeError("The 7-Zip file-stream integration no longer matches its pinned source.")
            Text = Text.replace(Original, Replacement)
        FileIO.write_text(Text)
        ShUtil.copyfile(Source, FileIO.parent / Source.name)
        Build = Working / "CPP/7zip/Bundles/Alone2"
        Binaries = []
        for Architecture in Architectures:
            if Architecture not in ["arm64", "x86_64"]:
                raise RuntimeError("Unsupported archive-helper architecture.")
            Output = "_" + Architecture
            Log = Working / (Architecture + ".log")
            with Log.open("w") as Stream:
                Result = Subprocess.run(["make", "-f", "makefile.gcc", "-j4", "O=" + Output,
                                         "CC=clang -arch " + Architecture + " -mmacosx-version-min=14.0",
                                         "CXX=clang++ -arch " + Architecture + " -mmacosx-version-min=14.0",
                                         "CFLAGS_BASE_LIST=-c -mmacosx-version-min=14.0", "CXXFLAGS_EXTRA=-std=c++17", "LFLAGS_STRIP="],
                                        cwd=Build, stdout=Stream, stderr=Subprocess.STDOUT)
            if Result.returncode:
                print(Log.read_text()[-12000:])
                raise RuntimeError("Could not build the archive reclamation helper.")
            Binaries.append(Build / Output / "7zz")
        Pending = Destination / "7zz-reclaim.pending"
        Subprocess.run(["xcrun", "lipo", "-create", *map(str, Binaries), "-output", str(Pending)], check=True)
        Pending.chmod(0o755)
        Pending.replace(Destination / "7zz-reclaim")
        ShUtil.copyfile(Archive, Destination / "7zip-source.tar.xz")
        ShUtil.copyfile(Source, Destination / Source.name)
        ShUtil.copyfile(Path(__file__), Destination / Path(__file__).name)
        Stamp.write_text(Signature)
        print("Built 7-Zip 26.03 with validated archive reclamation.")
