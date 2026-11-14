# Build the dual boot pieces: shellcode-r9q.bin (aarch64 binutils) and
# Reboot2Android.efi (clang + lld-link, freestanding PE/COFF for AArch64;
# -Brepro: no timestamp, so the same source gives the same file).
all: shellcode-r9q.bin Reboot2Android.efi

shellcode-r9q.bin: shellcode-r9q.S
	aarch64-linux-gnu-as $< -o shellcode-r9q.o
	aarch64-linux-gnu-objcopy -O binary shellcode-r9q.o $@

Reboot2Android.efi: reboot2android.c
	clang --target=aarch64-unknown-windows -ffreestanding -fno-stack-protector -fshort-wchar -O2 -Wall -Wextra -c $< -o reboot2android.obj
	lld-link -subsystem:efi_application -entry:efi_main -nodefaultlib -dynamicbase -fixed:no -Brepro -out:$@ reboot2android.obj

clean:
	rm -f *.o *.obj shellcode-r9q.bin Reboot2Android.efi
