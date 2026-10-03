#include <stdint.h>
#include "conv_commands.h"
#include "conv_input.h"
#include "conv_weight.h"

enum { CSB_BASE = 0x10000000u, STATUS = 0x80050000u };

static inline void write_csb(unsigned offset, unsigned value) {
    *(volatile uint32_t *)(uintptr_t)(CSB_BASE + offset) = value;
}

static inline unsigned read_csb(unsigned offset) {
    return *(volatile uint32_t *)(uintptr_t)(CSB_BASE + offset);
}

static unsigned wait_for_set(unsigned offset) {
    for (unsigned i = 0; i < 1048576; ++i)
        if (read_csb(offset) & 1u) return 0;
    return 2;
}

static unsigned wait_for_clear(unsigned offset) {
    for (unsigned i = 0; i < 1048576; ++i)
        if (!(read_csb(offset) & 1u)) return 0;
    return 2;
}

__attribute__((section(".text.start"), noreturn)) void _start(void) {
    unsigned status = 0;
    for (unsigned i = 0; i < CONV_CONFIG_COUNT; ++i)
        write_csb(conv_commands[i].offset, conv_commands[i].value);
    status = wait_for_set(0x300c); // CDMA CBUF flush complete
    if (!status) {
        for (unsigned i = CONV_CONFIG_COUNT; i < CONV_COMMAND_COUNT; ++i)
            write_csb(conv_commands[i].offset, conv_commands[i].value);
        status = wait_for_clear(0x9038); // SDP op complete
    }
    *(volatile uint32_t *)(uintptr_t)STATUS = status;
    asm volatile ("fence rw, rw" ::: "memory");
    asm volatile ("ebreak");
    for (;;) asm volatile ("nop");
}
