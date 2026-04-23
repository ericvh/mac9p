# Mac9P 1.1 (HERZOG)

**AI-generated note**: This file is an intentionally stylized, AI-written mirror of `README.md`, rendered in a Werner Herzog voice.  
It is meant to track the same facts and instructions as `README.md`, but with a different tone. If they diverge, treat `README.md` as canonical.

**Mac9P** is a tool that lets you mount [9P](https://en.wikipedia.org/wiki/9P_(protocol)) file systems on macOS. It is, in a sense, a rope bridge over an indifferent ravine: a protocol from another world, stretched across the modern system.

## Project status (2026)

The original design is a **kernel extension (kext)**, placing its hands directly upon the throat of the kernel, where modern macOS has become increasingly wary and restrictive.

In this repository there is now the beginning of a **kext-less rewrite using FSKit**—Apple’s user-space File System Extension framework—living in `fskit/`. It is the attempt to move the machinery out of the abyss of the kernel, into the harsh daylight of user space.

## Install

Run **Install Mac9P** from **Mac9P.dmg**.

## Uninstall

Run **Uninstall.tool** from **Mac9P.dmg**.

## Building

### Prerequisites

- **Xcode** (or Command Line Tools for userland tools).
- **Kernel Development Kit (KDK)** (only if you want to build the kernel extension).

### Compiling

In a terminal run:

```bash
cd mac9p
make all         # userland tools (mount/load/plugin)
make kext        # kernel extension (requires KDKROOT + matching KDK)
```

### FSKit (Path A) rewrite

The FSKit-based rewrite lives under `fskit/`. It is not wired into an Xcode project yet; the intention is that you create an Xcode app + **File System Extension** target and drop in the sources from `fskit/`.

See `fskit/README.md` for the current skeleton and mounting goals.

The testable heart of this expedition—its 9P client, its wire codec, and its mock server—now lives in `fskit-core/`. You can run its trials with:

```bash
make test-core
```

For the present, packaging instructions are gathered in `fskit/SETUP_XCODE.md`.

The FSKit volume has begun to speak in earnest: there is now an initial **read-only** implementation for lookup, attributes, enumeration, and reading—its nerves connected to the async 9P core in `fskit-core/`.

## Mounting

### From the Finder

*(Broken if the binary is not signed)*  
In Finder: **Go** → **Connect to Server...** and enter: *9p://sources.cs.bell-labs.com*.

### From a Terminal

```bash
mkdir /tmp/sources
mount -t 9p -onoauth sources.cs.bell-labs.com /tmp/sources
```

### Protocol versions (9P2000 / 9P2000.u / 9P2000.L)

Mac9P negotiates a 9P version during mount. You may demand a particular dialect of the protocol:

```bash
mount -t 9p -o vers=9P2000    -onoauth sources.cs.bell-labs.com /tmp/sources
mount -t 9p -o dotu          -onoauth sources.cs.bell-labs.com /tmp/sources
mount -t 9p -o vers=9P2000.L -onoauth sources.cs.bell-labs.com /tmp/sources
```

If your requested version is rejected by the server, Mac9P will fall back to another supported version—like an expedition forced to take a lesser pass when the mountain closes its route.

## Documentation

See **mount_9p(8)**.

## Troubleshooting

### Disable kext signing check

1. Boot into Recovery Mode by restarting your Mac while holding down *Command+R*.
2. Open a Terminal from **Utilities** → **Terminal** and run:

```bash
csrutil disable
csrutil enable --without kext
```

