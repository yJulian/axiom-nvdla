#include <stdint.h>

enum {
    NVDLA_MMIO_BASE = 0x10000000u,
    INPUT_ADDR = 0x80010000u,
    OUTPUT_ADDR = 0x80020000u,
    STATUS_ADDR = 0x80030000u,
    SDP_RDMA_BASE = 0x8000u,
    SDP_BASE = 0x9000u,
    CUBE_WIDTH = 1u,
    CUBE_HEIGHT = 1u,
    CUBE_CHANNELS = 8u,
    CUBE_STRIDE = 8u,
};

// Loose control path: a normal volatile store/load crosses AXI, the MMIO
// address decoder, and axi_csb before it reaches an NVDLA CSB register.
static inline void nvdla_write_register(uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(uintptr_t)(NVDLA_MMIO_BASE + offset) = value;
}

static inline uint32_t nvdla_read_register(uint32_t offset) {
    return *(volatile uint32_t *)(uintptr_t)(NVDLA_MMIO_BASE + offset);
}

static void select_sdp_register_group(void) {
    nvdla_write_register(SDP_BASE + 0x04, 0);       // SDP S_POINTER: group 0
    nvdla_write_register(SDP_RDMA_BASE + 0x04, 0);  // RDMA S_POINTER: group 0
}

static void configure_sdp_output(void) {
    nvdla_write_register(SDP_BASE + 0x3c, CUBE_WIDTH - 1);
    nvdla_write_register(SDP_BASE + 0x40, CUBE_HEIGHT - 1);
    nvdla_write_register(SDP_BASE + 0x44, CUBE_CHANNELS - 1);
    nvdla_write_register(SDP_BASE + 0x48, OUTPUT_ADDR);
    nvdla_write_register(SDP_BASE + 0x4c, 0);  // 32-bit address, high word
    nvdla_write_register(SDP_BASE + 0x50, CUBE_STRIDE); // line stride
    nvdla_write_register(SDP_BASE + 0x54, CUBE_STRIDE); // surface stride

    // BS ALU MAX with immediate zero is ReLU. Bypass BS multiply, BN and EW.
    nvdla_write_register(SDP_BASE + 0x58, 0x10);
    nvdla_write_register(SDP_BASE + 0x5c, 0);
    nvdla_write_register(SDP_BASE + 0x60, 0);
    nvdla_write_register(SDP_BASE + 0x6c, 1);
    nvdla_write_register(SDP_BASE + 0x80, 1);
    nvdla_write_register(SDP_BASE + 0xb0, 0);  // offline, one batch
    nvdla_write_register(SDP_BASE + 0xb4, 1);  // destination DMA
    nvdla_write_register(SDP_BASE + 0xc0, 0);  // INT8 format
    nvdla_write_register(SDP_BASE + 0xc4, 1);  // conversion scale
    nvdla_write_register(SDP_BASE + 0xc8, 0);  // conversion shift
}

static void configure_sdp_input_dma(void) {
    nvdla_write_register(SDP_RDMA_BASE + 0x0c, CUBE_WIDTH - 1);
    nvdla_write_register(SDP_RDMA_BASE + 0x10, CUBE_HEIGHT - 1);
    nvdla_write_register(SDP_RDMA_BASE + 0x14, CUBE_CHANNELS - 1);
    nvdla_write_register(SDP_RDMA_BASE + 0x18, INPUT_ADDR);
    nvdla_write_register(SDP_RDMA_BASE + 0x1c, 0);  // 32-bit address, high word
    nvdla_write_register(SDP_RDMA_BASE + 0x20, CUBE_STRIDE); // line stride
    nvdla_write_register(SDP_RDMA_BASE + 0x24, CUBE_STRIDE); // surface stride
    nvdla_write_register(SDP_RDMA_BASE + 0x28, 1);  // bypass BS DMA
    nvdla_write_register(SDP_RDMA_BASE + 0x40, 1);  // bypass BN DMA
    nvdla_write_register(SDP_RDMA_BASE + 0x58, 1);  // bypass EW DMA
    nvdla_write_register(SDP_RDMA_BASE + 0x70, 0); // feature mode
    nvdla_write_register(SDP_RDMA_BASE + 0x74, 1); // source DMA
}

static void start_sdp_relu(void) {
    nvdla_write_register(SDP_RDMA_BASE + 0x08, 1); // start input DMA first
    nvdla_write_register(SDP_BASE + 0x38, 1);      // then start SDP
}

static uint32_t wait_for_sdp(void) {
    // Match the tight path's completion criterion: SDP D_OP_ENABLE clears.
    for (unsigned i = 0; i < 4096; ++i) {
        if ((nvdla_read_register(SDP_BASE + 0x38) & 1u) == 0)
            return 0;
    }
    return 2;
}

__attribute__((section(".text.start"), noreturn)) void _start(void) {
    select_sdp_register_group();
    configure_sdp_output();
    configure_sdp_input_dma();
    start_sdp_relu();
    *(volatile uint32_t *)(uintptr_t)STATUS_ADDR = wait_for_sdp();
    asm volatile ("fence rw, rw" ::: "memory");
    asm volatile ("ebreak");
    for (;;) asm volatile ("nop");
}
