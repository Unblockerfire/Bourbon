# Universal cabextract build

Bourbon bundles `Source/Libraries/cabextract` for Winetricks. The binary is built
from the official [cabextract 1.11 source](https://www.cabextract.org.uk/cabextract-1.11.tar.gz).
The source archive SHA-256 is
`b5546db1155e4c718ff3d4b278573604f30dd64c3c5bfd4657cd089b823a3ac6`.

On a macOS 14-or-newer build host with the Xcode command-line tools, run:

```sh
Scripts/build-cabextract-universal.sh
```

The script downloads and verifies that source, builds separate arm64 and x86_64
slices with a macOS 14.0 minimum target, combines them with `lipo`, verifies both
slices, and prints the final binary SHA-256. It does not use a Homebrew cabextract
binary or introduce a dynamic Homebrew dependency.
