# Mac9P 1.1 #

**Mac9P** is a software that allows you to mount [9P](https://en.wikipedia.org/wiki/9P_(protocol)) file systems on a Mac OS X system.

## Project status (2026) ##

The original Mac9P design is a **kernel extension (kext)** that implements a 9P filesystem in-kernel.
On current macOS, kexts are increasingly restricted and require additional system configuration.

This repo now includes the start of a **kext-less rewrite using FSKit** (Apple’s user-space File System Extension framework), in `fskit/`.

## Install ##
Run **Install Mac9P** from the **Mac9P.dmg**.
 
## Uninstall ##

Run **Uninstall.tool** from the **Mac9P.dmg**.

## Building ##
### Prerequisites ###
* **Xcode** (or Command Line Tools for userland tools).
* **Kernel Development Kit (KDK)** (only if you want to build the kernel extension).

###  Compiling ###
In a terminal run:
```
cd mac9p
make all         # userland tools (mount/load/plugin)
make kext        # kernel extension (requires KDKROOT + matching KDK)

```

### FSKit (Path A) rewrite ###
The FSKit-based rewrite lives under `fskit/`. It is not wired into an Xcode project yet; the intent is that you create an Xcode app + **File System Extension** target and drop in the sources from `fskit/`.
See `fskit/README.md` for the current skeleton and mounting goals.

The **testable FSKit core** (9P client, wire codec, and mock-server tests) lives in `fskit-core/` and can be exercised with:

```
make test-core
```

See `fskit/SETUP_XCODE.md` for current packaging steps.

FSKit `Mac9PVolume` now has an initial **readonly implementation** (lookup/attributes/enumeration/read), backed by the async 9P client in `fskit-core/`.

## Mounting ##
### From the Finder ###
_(Broken if the binary is not signed)
**Go** -> **Connect to Server...**: _9p://sources.cs.bell-labs.com_.
### From a Terminal ###


```
mkdir /tmp/sources
mount -t 9p -onoauth sources.cs.bell-labs.com /tmp/sources

```

### Protocol versions (9P2000 / 9P2000.u / 9P2000.L)
Mac9P negotiates a 9P version during mount. You can request a specific version:

```
mount -t 9p -o vers=9P2000    -onoauth sources.cs.bell-labs.com /tmp/sources
mount -t 9p -o dotu          -onoauth sources.cs.bell-labs.com /tmp/sources
mount -t 9p -o vers=9P2000.L -onoauth sources.cs.bell-labs.com /tmp/sources
```

If the requested version is rejected by the server, Mac9P will fall back to another supported version.


## Documentation ##
See **mount_9p(8)**.

## Troubleshooting ##
### Disable kext signing check ###

1. Boot into Recovery Mode by restarting your mac while holding down _Command+R_.
2. Open a Terminal from **Utilities** -> **Terminal** and run:
```
csrutil disable
csrutil enable --without kext
```
