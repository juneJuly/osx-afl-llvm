#
# american fuzzy lop - LLVM instrumentation
# -----------------------------------------
#
# Written by Laszlo Szekeres <lszekeres@google.com> and
#            Michal Zalewski <lcamtuf@google.com>
#
# LLVM integration design comes from Laszlo Szekeres.
#
# Copyright 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#   http://www.apache.org/licenses/LICENSE-2.0
#

PREFIX      ?= /opt/local
#HELPER_PATH  = $(PREFIX)/lib/afl
HELPER_PATH  = .

LLVM_SRC_DIR = $(PWD)/llvm-3.5.0

BIN_PATH     = $(PREFIX)/bin

VERSION      = $(shell grep ^VERSION ../Makefile | cut -d= -f2 | sed 's/ //')

LLVM_CONFIG ?= llvm-config

CFLAGS      ?= -O3 -funroll-loops
CFLAGS      += -Wall -D_FORTIFY_SOURCE=2 -g -Wno-pointer-sign \
               -DAFL_PATH=\"$(HELPER_PATH)\" -DBIN_PATH=\"$(BIN_PATH)\" \
               -DVERSION=\"$(VERSION)\"

CXXFLAGS    ?= -O3 -funroll-loops
CXXFLAGS    += -Wall -D_FORTIFY_SOURCE=2 -g -v -Wno-pointer-sign \
               -DVERSION=\"$(VERSION)\"

CLANG_CFL    = `$(LLVM_CONFIG) --cxxflags` -fno-rtti $(CXXFLAGS)
CLANG_LFL    = `$(LLVM_CONFIG) --ldflags` $(LDFLAGS) `$(LLVM_CONFIG) --libs` -lncurses

# We were using llvm-config --bindir to get the location of clang, but
# this seems to be busted on some distros, so using the one in $PATH is
# probably better.

ifeq "$(origin CC)" "default"

CC           = /opt/local/bin/clang
CXX          = /opt/local/bin/clang++

endif

PROGS        = afl-llvm-pass.so afl-llvm-rt.o

all: test_deps $(PROGS) test_build all_done

osx: test_deps compile_llvm afl-llvm-rt.o ../afl-clang-fast test_build_osx

compile_llvm:
	./compile_llvm.sh

test_build_osx: afl-llvm-rt.o
	@echo "[*] Testing the CC wrapper and instrumentation output..."
	unset AFL_USE_ASAN AFL_USE_MSAN AFL_DEFER_FORKSRV; AFL_QUIET=1 AFL_INST_RATIO=100 AFL_PATH=. AFL_CC=$(LLVM_SRC_DIR)/build/Release+Asserts/bin/clang ../afl-clang-fast $(CFLAGS) ../test-instr.c -o test-instr $(LDFLAGS)
	echo 0 | ../afl-showmap -m none -q -o .test-instr0 ./test-instr
	echo 1 | ../afl-showmap -m none -q -o .test-instr1 ./test-instr
	@rm -f test-instr
	@cmp -s .test-instr0 .test-instr1; DR="$$?"; rm -f .test-instr0 .test-instr1; if [ "$$DR" = "0" ]; then echo; echo "Oops, the instrumentation does not seem to be behaving correctly!"; echo; echo "Please ping <lcamtuf@google.com> to troubleshoot the issue."; echo; exit 1; fi
	@echo "[+] All right, the instrumentation seems to be working!"

test_deps:
	@echo "[*] Checking for working 'llvm-config'..."
	@which $(LLVM_CONFIG) >/dev/null 2>&1 || ( echo "[-] Oops, can't find 'llvm-config'. Install clang or set \$$LLVM_CONFIG or \$$PATH beforehand."; echo "    (Sometimes, the binary will be named llvm-config-3.5 or something like that.)"; exit 1 )
	@echo "[*] Checking for working '$(CC)'..."
	@which $(CC) >/dev/null 2>&1 || ( echo "[-] Oops, can't find '$(CC)'. Make sure that it's in your \$$PATH (or set \$$CC and \$$CXX)."; exit 1 )
	@echo "[*] Checking for '../afl-showmap'..."
	@test -f ../afl-showmap || ( echo "[-] Oops, can't find '../afl-showmap'. Be sure to compile AFL first."; exit 1 )
	@echo "[+] All set and ready to build."

../afl-clang-fast: afl-clang-fast.c | test_deps
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)
	ln -sf afl-clang-fast ../afl-clang-fast++

afl-llvm-pass.so: afl-llvm-pass.so.cc | test_deps
	$(CXX) $(CLANG_CFL) -dynamiclib $< -o $@ $(CLANG_LFL)

afl-llvm-rt.o: afl-llvm-rt.o.c | test_deps
	$(CC) $(CFLAGS) -fPIC -c $< -o $@

test_build: $(PROGS)
	@echo "[*] Testing the CC wrapper and instrumentation output..."
	unset AFL_USE_ASAN AFL_USE_MSAN AFL_DEFER_FORKSRV; AFL_QUIET=1 AFL_INST_RATIO=100 AFL_PATH=. AFL_CC=$(CC) ../afl-clang-fast $(CFLAGS) ../test-instr.c -o test-instr $(LDFLAGS)
	echo 0 | ../afl-showmap -m none -q -o .test-instr0 ./test-instr
	echo 1 | ../afl-showmap -m none -q -o .test-instr1 ./test-instr
	@rm -f test-instr
	@cmp -s .test-instr0 .test-instr1; DR="$$?"; rm -f .test-instr0 .test-instr1; if [ "$$DR" = "0" ]; then echo; echo "Oops, the instrumentation does not seem to be behaving correctly!"; echo; echo "Please ping <lcamtuf@google.com> to troubleshoot the issue."; echo; exit 1; fi
	@echo "[+] All right, the instrumentation seems to be working!"

all_done: test_build
	@echo "[+] All done! You can now use '../afl-clang-fast' to compile programs."

.NOTPARALLEL: clean

clean:
	rm -f *.o *.so *~ a.out core core.[1-9][0-9]* test-instr .test-instr0 .test-instr1 
	rm -f $(PROGS) ../afl-clang-fast++

superclean: clean
	rm -rf $(LLVM_SRC_DIR) *.dSYM *.xz
