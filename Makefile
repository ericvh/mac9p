MACOSX_DEPLOYMENT_TARGET ?= 11.0
#export ARCHS=-arch x86_64 -arch arm64

SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
CC ?= clang

WARNINGS ?= -Wall -Wextra -Wno-missing-braces -Wno-private-extern
ifeq ($(WERROR),1)
WARNINGS += -Werror
endif

export CFLAGS = -g -isysroot "$(SDKROOT)" -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) $(WARNINGS) #-DNDEBUG
export LFLAGS = -g -isysroot "$(SDKROOT)" -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)

DIRS=load mount plugin

all clean:
	@for i in $(DIRS); do\
		$(MAKE) -C $$i $(MAKEFLAGS) $@ || exit 1;\
	done

test: tests/test_versneg tests/test_fcall_codec
	@echo "Running tests/test_versneg"
	./tests/test_versneg
	@echo "Running tests/test_fcall_codec"
	./tests/test_fcall_codec

test-kext: test

test-core:
	@echo "Running SwiftPM tests (fskit-core)"
	@cd fskit-core && swift test

test-all: test-core test-kext

tests/test_versneg: tests/test_versneg.c common/versneg.c common/versneg.h
	@mkdir -p tests
	$(CC) $(CFLAGS) -Icommon -o $@ tests/test_versneg.c common/versneg.c

tests/test_fcall_codec: tests/test_fcall_codec.c kext/fcall.c kext/plan9.h kext/fcall.h
	@mkdir -p tests
	$(CC) $(CFLAGS) -Ikext -o $@ tests/test_fcall_codec.c kext/fcall.c

kext:
	@$(MAKE) -C kext $(MAKEFLAGS) all

pkg dmg:
	@$(MAKE) -C inst $(MAKEFLAGS) $@
