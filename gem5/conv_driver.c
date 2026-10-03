#include <stdint.h>

enum { CONTROL = 0x10010000, OUTPUT = 0x80040000, STATUS = 0x80050000 };

static long syscall3(long number, long arg0, long arg1, long arg2) {
    register long a0 asm("a0") = arg0;
    register long a1 asm("a1") = arg1;
    register long a2 asm("a2") = arg2;
    register long a7 asm("a7") = number;
    asm volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}

static __attribute__((noreturn)) void stop(int code) {
    syscall3(93, code, 0, 0);
    for (;;) {}
}

static void print(const char *message) {
    unsigned length = 0;
    while (message[length]) ++length;
    syscall3(64, 1, (long)message, length);
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

static uint32_t output_crc(void) {
    static uint32_t table[256];
    for (unsigned i = 0; i < 256; ++i) {
        uint32_t value = i;
        for (unsigned bit = 0; bit < 8; ++bit)
            value = (value >> 1) ^ (0xEDB88320u & -(value & 1u));
        table[i] = value;
    }
    volatile const uint64_t *data = (volatile const uint64_t *)(uintptr_t)OUTPUT;
    uint32_t crc = ~0u;
    for (unsigned word = 0; word < 0x1500 / 8; ++word) {
        uint64_t value = data[word];
        for (unsigned byte = 0; byte < 8; ++byte) {
            crc = table[(crc ^ (uint8_t)value) & 255u] ^ (crc >> 8);
            value >>= 8;
        }
    }
    return ~crc;
}

__attribute__((noreturn)) void _start(void) {
    volatile uint64_t *control = (volatile uint64_t *)(uintptr_t)CONTROL;
    control[0] = 1;
    unsigned polls = 0;
    while ((control[0] & 2) == 0 && ++polls < 20000000) {}
    if (polls == 20000000) { print("FAIL: RTL timeout\n"); stop(1); }
    uint64_t cycles = control[2];
    if (control[0] & 4) { print("FAIL: illegal instruction\n"); stop(2); }
    if (*(volatile uint32_t *)(uintptr_t)STATUS) {
        print("FAIL: NVDLA timeout\n"); stop(3);
    }
    if (output_crc() != 0x8C467827u) {
        print("FAIL: convolution CRC mismatch\n"); stop(4);
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
