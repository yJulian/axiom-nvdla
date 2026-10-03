#include <stdint.h>
#include "conv_input.h"
#include "conv_weight.h"

enum { STATUS = 0x80050000u };

// One task instruction configures CDMA, CSC, CMAC, CACC and SDP. The exact
// register sequence is local to cvxif_sdp and backed by the nv_small trace.
static inline unsigned launch_conv(void) {
    uintptr_t result;
    asm volatile (".insn r 0x0b, 2, 0, %0, x0, x0" : "=r"(result) :: "memory");
    return (unsigned)result;
}

static inline unsigned wait_for_conv(void) {
    uintptr_t result;
    asm volatile (".insn r 0x0b, 1, 0, %0, x0, x0" : "=r"(result) :: "memory");
    return (unsigned)result;
}

__attribute__((section(".text.start"), noreturn)) void _start(void) {
    unsigned status = launch_conv();
    if (!status) status = wait_for_conv();
    *(volatile uint32_t *)(uintptr_t)STATUS = status;
    asm volatile ("fence rw, rw" ::: "memory");
    asm volatile ("ebreak");
    for (;;) asm volatile ("nop");
}
