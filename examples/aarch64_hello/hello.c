/* Smallest valid aarch64-none-elf object: a single _start that
 * spins forever via WFE. No libc, no syscalls — the toolchain is
 * `-ffreestanding -nostdlib`. */

void _start(void) {
    for (;;) {
        __asm__ volatile("wfe");
    }
}
