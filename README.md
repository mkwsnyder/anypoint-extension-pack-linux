# Anypoint Code Builder for Linux (unofficial)

Salesforce publishes the [Anypoint Extension Pack](https://marketplace.visualstudio.com/items?itemName=salesforce.mule-dx-extension-pack) for VS Code only for Windows and macOS. The extensions' code already handles Linux. Only three bundled binaries are tied to an OS:

| Extension | Bundled binary | Linux replacement |
|---|---|---|
| `mule-dx-dependencies` | Temurin JDK | Same Temurin release for Linux, from Adoptium |
| `mule-dx-api-component` | Node.js runtime | Same Node.js release for Linux, from nodejs.org |
| `mule-dx-api-component` | `acv` (API governance validator) | Built from [aml-org/amf-custom-validator](https://github.com/aml-org/amf-custom-validator) source |

`build.sh` downloads the official macOS builds from the VS Code Marketplace, swaps in the Linux binaries above, and repackages everything as `linux-x64` or `linux-arm64` VSIXes. `install.sh` installs them into VS Code.

This repository contains only scripts. It does not include or redistribute any Salesforce software.

> **Not affiliated with Salesforce or MuleSoft.** The extensions are licensed under the [Salesforce Main Services Agreement](https://www.salesforce.com/content/dam/web/en_us/www/documents/legal/Salesforce_MSA.pdf); running `build.sh` downloads them from the Marketplace under those terms. Build for your own use and don't share the VSIXes you build.

## Requirements

- Linux on x64 or arm64
- VS Code 1.99.3 or later
- `bash`, `curl`, `jq`, `unzip`, `zip`, `tar`, `xz`, `git`, `file`, coreutils, and Go 1.19 or later

  ```sh
  sudo pacman -S --needed curl jq unzip zip xz git file go      # Arch
  sudo apt install curl jq unzip zip xz-utils git file golang   # Debian/Ubuntu
  ```
- About 2 GB of downloads and 6 GB of free disk space while building

## Usage

```sh
./build.sh            # writes VSIXes to ./dist
./install.sh          # installs them into `code`
```

To install into VSCodium or Code-OSS, set `CODE`, e.g. `CODE=codium ./install.sh`. `install.sh` installs the extensions in dependency order. If an extension's dependency isn't installed yet, VS Code looks for it on the Marketplace, which has no Linux builds.

To cross-build, set `ARCH`, e.g. `ARCH=arm64 ./build.sh`. Downloads are cached in `./work`, which you can delete at any time.

## Updating

These extensions won't auto-update. To update, rerun `./build.sh && ./install.sh`; the build always uses the latest stable Marketplace release.

## Safety checks

`build.sh` stops instead of producing a broken build when:

- a JDK or Node.js download fails its checksum
- the bundled JDK is no longer Temurin
- the shipped `acv` was built from different dependencies than the pinned source commit (update `acv_commit` in `build.sh`)
- a macOS binary is left in the output with no Linux counterpart, which means a new release added another platform-specific binary

When the build machine's architecture matches the target, `build.sh` also runs the swapped-in `java`, `node`, and `acv` binaries once. CI runs the build weekly on x64 and arm64 to catch breaking upstream releases.

## Known limitations

- The AI assistant's "run locally" tool opens Mule in an external terminal window, and Salesforce only implemented that for macOS and Windows. On Linux it fails with "Unsupported platform". Running and debugging from the normal IDE commands doesn't use this code path.
- Microsoft's Marketplace terms allow Marketplace extensions only in Microsoft's own VS Code builds. Using them in VSCodium or Code-OSS is at your discretion.

## License

The scripts in this repository are MIT-licensed. That license does not cover the Salesforce extensions they download.
