#include <stdint.h>

enum {
    INPUT_ADDR = 0x80010000u,
    OUTPUT_ADDR = 0x80020000u,
    STATUS_ADDR = 0x80030000u,
};

// Custom-0/funct3=0 configures and launches one 1x1x8 INT8 SDP ReLU task.
// rs1 = input AXI address, rs2 = output AXI address, rd = launch status.
static inline uint32_t nvdla_relu8(uintptr_t input, uintptr_t output) {
    uintptr_t status;
    asm volatile (".insn r 0x0b, 0, 0, %0, %1, %2"
                  : "=r"(status) : "r"(input), "r"(output) : "memory");
    return (uint32_t)status;
}

// Custom-0/funct3=1 waits until NVDLA clears SDP D_OP_ENABLE.
// rd = 0 on completion, 2 if the hardware poll limit is reached.
static inline uint32_t nvdla_wait(void) {
    uintptr_t status;
    asm volatile (".insn r 0x0b, 1, 0, %0, x0, x0"
                  : "=r"(status) :: "memory");
    return (uint32_t)status;
}

__attribute__((section(".text.start"), noreturn)) void _start(void) {
    uint32_t launch_status = nvdla_relu8(INPUT_ADDR, OUTPUT_ADDR);
    uint32_t completion_status = launch_status ? 0 : nvdla_wait();
    *(volatile uint32_t *)(uintptr_t)STATUS_ADDR =
        launch_status | (completion_status << 8);
    asm volatile ("fence rw, rw" ::: "memory");
    asm volatile ("ebreak");
    for (;;) asm volatile ("nop");
}
