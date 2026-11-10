# Third-party notices and asset scope

The tool code in this repository is distributed under the MIT license. This is an independent project; game names identify the supported product.

## Public source

The source package contains the Python application, browser UI, C# launcher, C++ adapter, scripts and interface metadata. It excludes original game binaries, machine-code comparison tables, initial PKM inputs and input snapshots.

## Desktop release

The v1103.2, v1106 and v1108.5 EXEs are separate desktop distributions. Each includes a private CPython 3.12 runtime and its `LICENSE.txt`, the tool's native host, compatibility comparison data and matching initial inputs. It loads the original engine DLL and game resource archives from the user's installation; those game components are not included in the EXE.

The MIT grant covers the tool code. It does not relicense game-related inputs, extracted comparison bytes, third-party components or their trademarks. CPython and its bundled components retain the licenses shipped in the runtime. Windows SDK, MSVC and .NET Framework are build prerequisites and are not included in the source archive.

Career-save import uses fmsave 0.9.0 (MIT) and backports.zstd 1.8.0 (PSF-2.0 with the bundled Zstandard license). The public source lists these packages as dependencies. Desktop builds include the packages and their license files.

## Native Mac extension in this fork

The `macos/` directory adds Swift/SwiftUI tool code, an Objective-C++ match host, an arm64 ABI bridge, tests and build scripts under the same MIT license. The upstream author and contributors retain attribution for the original FM Tactics Lab project and Windows implementation.

The Mac host loads the complete original engine and reads resources and the bundled test fixture from the user's own supported FM27 installation. No game binary, extracted executable slice, disassembly, resource archive, PKM fixture or career save is included in the public Mac source or app bundle. SHA-256 fingerprints and version-specific adapter offsets identify the supported installed build; they do not grant rights to game components. Local research files, runtime logs and build products are ignored by Git.

The Mac client uses Apple system frameworks. Mac 0.5 also bundles a standalone SaveReader made with PyInstaller 6.17.0 and CPython 3.13, including fmsave 0.9.0 (MIT), backports.zstd 1.8.0 (PSF-2.0 and bundled Zstandard license), CPython (PSF), and PyInstaller (GPL with its application-bundling exception). Their license files are included under `Contents/Resources/SaveReader/licenses/`. No Node runtime is included. Apple Command Line Tools and Python 3.11+ are build prerequisites. The Mac role/instruction/formation/set-piece functional metadata is adapted from the upstream public editor; game binary dumps and extracted private catalogs are excluded. This fork is an independent extension, not an official Sports Interactive or SEGA product.
