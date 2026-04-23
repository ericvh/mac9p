MACOSX_DEPLOYMENT_TARGET ?= 11.0
SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)

# Building kexts on modern macOS requires a matching Kernel Development Kit (KDK).
# Point KDKROOT at an installed KDK, e.g.:
#   /Library/Developer/KDKs/KDK_15.5_24F74.kdk
KDKROOT ?= $(shell ls -d /Library/Developer/KDKs/KDK_*.kdk 2>/dev/null | tail -n 1)
KERNEL_HEADERS ?= $(KDKROOT)/System/Library/Frameworks/Kernel.framework/Headers

CFLAGS+=-mkernel -nostdinc  -fasm-blocks\
 -force_cpusubtype_ALL -msoft-float -Os\
 -finline -std=c99\
 -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT\
 -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)\
 -I"$(KERNEL_HEADERS)"\

LFLAGS+=-Xlinker -kext -nostdlib -lkmod

TARG=9p

OFILES=\
	auth.o\
	crypt.o\
	fcall.o\
	proto.o\
	socket.o\
	vfsops.o\
	vnops.o\

HFILES=\
	9p.h\
	fcall.h\
	plan9.h\

all:
	@if [ ! -d "$(KERNEL_HEADERS)" ]; then \
		echo "Missing KDK kernel headers. Install a matching KDK and set KDKROOT."; \
		echo "Expected: $(KERNEL_HEADERS)"; \
		exit 1; \
	fi
	@$(MAKE) $(TARG)

$(TARG): $(OFILES)
	$(CC) $(ARCHS) -o $@ $(OFILES) $(LFLAGS)

%.o: %.c $(HFILES)
	$(CC) $(ARCHS) $(CFLAGS) -c $*.c

clean:
	rm -fr $(TARG) *.o *.dSYM
