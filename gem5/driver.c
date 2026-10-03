#include <stdint.h>

// A freestanding SE driver avoids libc startup dominating the short RTL job.
// This gem5 CPU only initializes shared memory and checks the RTL CVA6 run.
enum { CONTROL = 0x10010000, INPUT = 0x80010000, OUTPUT = 0x80020000,
       RESULT = 0x80030000 };

static long syscall3(long number, long arg0, long arg1, long arg2) {
    register long a0 asm("a0") = arg0;
    register long a1 asm("a1") = arg1;
    register long a2 asm("a2") = arg2;
    register long a7 asm("a7") = number;
    asm volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}

static void write_text(const char *message) {
    unsigned length = 0;
    while (message[length]) ++length;
    syscall3(64, 1, (long)message, length);
}

static __attribute__((noreturn)) void stop(int code) {
    syscall3(93, code, 0, 0);
    for (;;) {}
}

static char *decimal(char *end, uint64_t value) {
    char reversed[24];
    unsigned length = 0;
    do {
        reversed[length++] = '0' + value % 10;
        value /= 10;
    } while (value);
    while (length) *end++ = reversed[--length];
    return end;
}

__attribute__((noreturn)) void _start(void) {
    static const uint8_t input[8] = {0x80, 0xff, 0, 1, 2, 127, 0xd6, 42};
    volatile uint8_t *src = (volatile uint8_t *)(uintptr_t)INPUT;
    volatile uint8_t *dst = (volatile uint8_t *)(uintptr_t)OUTPUT;
    volatile uint32_t *result = (volatile uint32_t *)(uintptr_t)RESULT;
    volatile uint64_t *control = (volatile uint64_t *)(uintptr_t)CONTROL;
    for (unsigned i = 0; i < 8; ++i) {
        src[i] = input[i];
        dst[i] = 0xa5;
    }
    *result = 0xa5a5a5a5;
    asm volatile ("fence rw, rw" ::: "memory");
    control[0] = 1;
    unsigned polls = 0;
    while ((control[0] & 2) == 0 && ++polls < 100000) {}
    if (polls == 100000) {
        write_text("FAIL: RTL CPU did not finish\n");
        stop(1);
    }
    uint64_t cycles = control[2];
    if (control[0] & 4) {
        write_text("FAIL: RTL CPU executed illegal instruction\n");
        stop(2);
    }
    if (*result != 0) {
        write_text("FAIL: NVDLA returned nonzero status\n");
        stop(3);
    }
    for (unsigned i = 0; i < 8; ++i) {
        uint8_t expected = input[i] & 0x80 ? 0 : input[i];
        if (dst[i] != expected) {
            write_text("FAIL: NVDLA output mismatch\n");
            stop(4);
        }
    }
    char line[96];
    char *end = line;
    const char *prefix = "RESULT cycles=";
    while (*prefix) *end++ = *prefix++;
    end = decimal(end, cycles);
    prefix = " polls=";
    while (*prefix) *end++ = *prefix++;
    end = decimal(end, polls);
    prefix = " status=PASS\n";
    while (*prefix) *end++ = *prefix++;
    syscall3(64, 1, (long)line, end - line);
    stop(0);
}
