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

test: tests/test_versneg
	@./tests/test_versneg

tests/test_versneg: tests/test_versneg.c common/versneg.c common/versneg.h
	@mkdir -p tests
	$(CC) $(CFLAGS) -Icommon -o $@ tests/test_versneg.c common/versneg.c

kext:
	@$(MAKE) -C kext $(MAKEFLAGS) all

pkg dmg:
	@$(MAKE) -C inst $(MAKEFLAGS) $@
