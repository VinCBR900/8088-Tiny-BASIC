# Makefile contributed by jtsiomb

src = basic.asm

.PHONY: all
all: basic.com

basic.com: $(src)
	nasm -f bin -l basic.lst -o $@ $(src)
	@echo "ROM_END offset (last code byte boundary): 0x$$(awk '/TIMES 0x1000-/{print $$2; exit}' basic.lst)"

.PHONY: clean
clean:
	$(RM) basic.com

.PHONY: rundosbox
rundosbox: basic.com
	dosbox $<

.PHONY: runqemu
runqemu: basic.com
	@echo "Provide a DOS image/environment to run basic.com under qemu."
