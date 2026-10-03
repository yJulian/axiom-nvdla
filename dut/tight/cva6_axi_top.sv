// Tight CPU wrapper: CVA6 with a CV-X-IF to NVDLA CSB and an AXI atomics
// adapter. AXI still carries instruction/data and reaches the shared RAM.

module cva6_axi_top import ariane_pkg::*; (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic [63:0]                  boot_addr_i,
  input  logic [63:0]                  hart_id_i,
  input  logic [1:0]                   irq_i,
  input  logic                         ipi_i,
  input  logic                         time_irq_i,
  input  logic                         debug_req_i,

  // Additional Debug Channels
  output logic                         ebreak_o,
  output logic                         illegal_instr_o,
  output logic [63:0]                  program_counter,

  // AXI AW Channel (out)   -   Write Address (M -> S)
  output logic                         noc_req_aw_valid_o,
  output logic [ariane_axi::IdWidth-1:0] noc_req_aw_id_o,
  output logic [63:0]                  noc_req_aw_addr_o,
  output logic [7:0]                   noc_req_aw_len_o,
  output logic [2:0]                   noc_req_aw_size_o,
  output logic [3:0]                   noc_req_aw_cache_o,
  input  logic                         noc_resp_aw_ready_i,

  // AXI W Channel (out)    -   Write Data (M -> S)
  output logic                         noc_req_w_valid_o,
  output logic [63:0]                  noc_req_w_data_o,
  output logic [ariane_axi::StrbWidth-1:0] noc_req_w_strb_o,
  output logic                         noc_req_w_last_o,
  input  logic                         noc_resp_w_ready_i,

  // AXI B Channel (in)     -   Write Response (S -> M)
  input  logic                         noc_resp_b_valid_i,
  input  logic [ariane_axi::IdWidth-1:0] noc_resp_b_id_i,
  input  logic [1:0]                   noc_resp_b_resp_i,
  output logic                         noc_req_b_ready_o,

  // AXI AR Channel (out)   -   Read Address (M -> S)
  output logic                         noc_req_ar_valid_o,
  output logic [ariane_axi::IdWidth-1:0] noc_req_ar_id_o,
  output logic [63:0]                  noc_req_ar_addr_o,
  output logic [7:0]                   noc_req_ar_len_o,
  output logic [2:0]                   noc_req_ar_size_o,
  output logic [2:0]                   noc_req_ar_prot_o,
  output logic [3:0]                   noc_req_ar_cache_o,
  input  logic                         noc_resp_ar_ready_i,

  // AXI R Channel (in)     -   Read Result (S -> M)
  input  logic                         noc_resp_r_valid_i,
  input  logic [ariane_axi::IdWidth-1:0] noc_resp_r_id_i,
  input  logic [63:0]                  noc_resp_r_data_i,
  input  logic                         noc_resp_r_last_i,
  input  logic [1:0]                   noc_resp_r_resp_i,
  output logic                         noc_req_r_ready_o,
  output logic                         csb_valid,
  input  logic                         csb_ready,
  output logic [15:0]                  csb_addr,
  output logic [31:0]                  csb_wdata,
  output logic                         csb_write,
  output logic                         csb_nposted,
  input  logic                         csb_resp_valid,
  input  logic [31:0]                  csb_resp_data
);

  localparam config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  ariane_axi::req_t  noc_req_o;
  ariane_axi::resp_t noc_resp_i;

  // ---------------------------------------------------------------------
  // AXI RISC-V atomics adapter
  // ---------------------------------------------------------------------
  // CVA6 issues AMOs and LR/SC using AXI atomic/exclusive transactions.
  // This adapter resolves them into ordinary AXI reads and writes before
  // traffic reaches the shared crossbar.

  // Unused downstream outputs of the atomics adapter
  logic [2:0]                       mst_aw_prot;
  logic [3:0]                       mst_aw_region, mst_ar_region;
  logic [5:0]                       mst_aw_atop;
  // AxCACHE from the adapter is a constant CACHE_MODIFIABLE (the core
  // hardcodes it, see the PMA export below), so it carries no information
  // and is left unconnected.
  logic [3:0]                       mst_aw_cache, mst_ar_cache;
  logic [1:0]                       mst_aw_burst, mst_ar_burst;
  logic                             mst_aw_lock, mst_ar_lock;
  logic [3:0]                       mst_aw_qos, mst_ar_qos;
  logic [ariane_axi::UserWidth-1:0] mst_aw_user, mst_ar_user, mst_w_user;

  axi_riscv_atomics #(
    .AXI_ADDR_WIDTH     ( ariane_axi::AddrWidth ),
    .AXI_DATA_WIDTH     ( ariane_axi::DataWidth ),
    .AXI_ID_WIDTH       ( ariane_axi::IdWidth   ),
    .AXI_USER_WIDTH     ( ariane_axi::UserWidth ),
    .AXI_MAX_WRITE_TXNS ( 1                     ),
    .RISCV_WORD_WIDTH   ( 64                    )
  ) i_axi_riscv_atomics (
    .clk_i           ( clk_i                ),
    .rst_ni          ( rst_ni               ),

    // Slave side: connected to the CVA6 NoC request/response structs
    .slv_aw_addr_i   ( noc_req_o.aw.addr    ),
    .slv_aw_prot_i   ( noc_req_o.aw.prot    ),
    .slv_aw_region_i ( noc_req_o.aw.region  ),
    .slv_aw_atop_i   ( noc_req_o.aw.atop    ),
    .slv_aw_len_i    ( noc_req_o.aw.len     ),
    .slv_aw_size_i   ( noc_req_o.aw.size    ),
    .slv_aw_burst_i  ( noc_req_o.aw.burst   ),
    .slv_aw_lock_i   ( noc_req_o.aw.lock    ),
    .slv_aw_cache_i  ( noc_req_o.aw.cache   ),
    .slv_aw_qos_i    ( noc_req_o.aw.qos     ),
    .slv_aw_id_i     ( noc_req_o.aw.id      ),
    .slv_aw_user_i   ( noc_req_o.aw.user    ),
    .slv_aw_ready_o  ( noc_resp_i.aw_ready  ),
    .slv_aw_valid_i  ( noc_req_o.aw_valid   ),

    .slv_ar_addr_i   ( noc_req_o.ar.addr    ),
    .slv_ar_prot_i   ( noc_req_o.ar.prot    ),
    .slv_ar_region_i ( noc_req_o.ar.region  ),
    .slv_ar_len_i    ( noc_req_o.ar.len     ),
    .slv_ar_size_i   ( noc_req_o.ar.size    ),
    .slv_ar_burst_i  ( noc_req_o.ar.burst   ),
    .slv_ar_lock_i   ( noc_req_o.ar.lock    ),
    .slv_ar_cache_i  ( noc_req_o.ar.cache   ),
    .slv_ar_qos_i    ( noc_req_o.ar.qos     ),
    .slv_ar_id_i     ( noc_req_o.ar.id      ),
    .slv_ar_user_i   ( noc_req_o.ar.user    ),
    .slv_ar_ready_o  ( noc_resp_i.ar_ready  ),
    .slv_ar_valid_i  ( noc_req_o.ar_valid   ),

    .slv_w_data_i    ( noc_req_o.w.data     ),
    .slv_w_strb_i    ( noc_req_o.w.strb     ),
    .slv_w_user_i    ( noc_req_o.w.user     ),
    .slv_w_last_i    ( noc_req_o.w.last     ),
    .slv_w_ready_o   ( noc_resp_i.w_ready   ),
    .slv_w_valid_i   ( noc_req_o.w_valid    ),

    .slv_r_data_o    ( noc_resp_i.r.data    ),
    .slv_r_resp_o    ( noc_resp_i.r.resp    ),
    .slv_r_last_o    ( noc_resp_i.r.last    ),
    .slv_r_id_o      ( noc_resp_i.r.id      ),
    .slv_r_user_o    ( noc_resp_i.r.user    ),
    .slv_r_ready_i   ( noc_req_o.r_ready    ),
    .slv_r_valid_o   ( noc_resp_i.r_valid   ),

    .slv_b_resp_o    ( noc_resp_i.b.resp    ),
    .slv_b_id_o      ( noc_resp_i.b.id      ),
    .slv_b_user_o    ( noc_resp_i.b.user    ),
    .slv_b_ready_i   ( noc_req_o.b_ready    ),
    .slv_b_valid_o   ( noc_resp_i.b_valid   ),

    // Master side: plain AXI towards the shared crossbar
    .mst_aw_addr_o   ( noc_req_aw_addr_o    ),
    .mst_aw_prot_o   ( mst_aw_prot          ),
    .mst_aw_region_o ( mst_aw_region        ),
    .mst_aw_atop_o   ( mst_aw_atop          ),
    .mst_aw_len_o    ( noc_req_aw_len_o     ),
    .mst_aw_size_o   ( noc_req_aw_size_o    ),
    .mst_aw_burst_o  ( mst_aw_burst         ),
    .mst_aw_lock_o   ( mst_aw_lock          ),
    .mst_aw_cache_o  ( mst_aw_cache         ),
    .mst_aw_qos_o    ( mst_aw_qos           ),
    .mst_aw_id_o     ( noc_req_aw_id_o      ),
    .mst_aw_user_o   ( mst_aw_user          ),
    .mst_aw_ready_i  ( noc_resp_aw_ready_i  ),
    .mst_aw_valid_o  ( noc_req_aw_valid_o   ),

    .mst_ar_addr_o   ( noc_req_ar_addr_o    ),
    .mst_ar_prot_o   ( noc_req_ar_prot_o    ),
    .mst_ar_region_o ( mst_ar_region        ),
    .mst_ar_len_o    ( noc_req_ar_len_o     ),
    .mst_ar_size_o   ( noc_req_ar_size_o    ),
    .mst_ar_burst_o  ( mst_ar_burst         ),
    .mst_ar_lock_o   ( mst_ar_lock          ),
    .mst_ar_cache_o  ( mst_ar_cache         ),
    .mst_ar_qos_o    ( mst_ar_qos           ),
    .mst_ar_id_o     ( noc_req_ar_id_o      ),
    .mst_ar_user_o   ( mst_ar_user          ),
    .mst_ar_ready_i  ( noc_resp_ar_ready_i  ),
    .mst_ar_valid_o  ( noc_req_ar_valid_o   ),

    .mst_w_data_o    ( noc_req_w_data_o     ),
    .mst_w_strb_o    ( noc_req_w_strb_o     ),
    .mst_w_user_o    ( mst_w_user           ),
    .mst_w_last_o    ( noc_req_w_last_o     ),
    .mst_w_ready_i   ( noc_resp_w_ready_i   ),
    .mst_w_valid_o   ( noc_req_w_valid_o    ),

    .mst_r_data_i    ( noc_resp_r_data_i    ),
    .mst_r_resp_i    ( noc_resp_r_resp_i    ),
    .mst_r_last_i    ( noc_resp_r_last_i    ),
    .mst_r_id_i      ( noc_resp_r_id_i      ),
    .mst_r_user_i    ( '0                   ),
    .mst_r_ready_o   ( noc_req_r_ready_o    ),
    .mst_r_valid_i   ( noc_resp_r_valid_i   ),

    .mst_b_resp_i    ( noc_resp_b_resp_i    ),
    .mst_b_id_i      ( noc_resp_b_id_i      ),
    .mst_b_user_i    ( '0                   ),
    .mst_b_ready_o   ( noc_req_b_ready_o    ),
    .mst_b_valid_i   ( noc_resp_b_valid_i   )
  );



  ariane_nvdla #(
    .CVA6Cfg ( CVA6Cfg ),
    .AxiAddrWidth ( ariane_axi::AddrWidth ),
    .AxiDataWidth ( ariane_axi::DataWidth ),
    .AxiIdWidth   ( ariane_axi::IdWidth ),
    .axi_ar_chan_t ( ariane_axi::ar_chan_t ),
    .axi_aw_chan_t ( ariane_axi::aw_chan_t ),
    .axi_w_chan_t  ( ariane_axi::w_chan_t  ),
    .noc_req_t     ( ariane_axi::req_t     ),
    .noc_resp_t    ( ariane_axi::resp_t    )
  ) i_ariane (
    .clk_i                ( clk_i                     ),
    .rst_ni               ( rst_ni                    ),
    .boot_addr_i          ( boot_addr_i[CVA6Cfg.VLEN-1:0] ),
    .hart_id_i            ( hart_id_i[CVA6Cfg.XLEN-1:0]   ),
    .irq_i                ( irq_i                     ),
    .ipi_i                ( ipi_i                     ),
    .time_irq_i           ( time_irq_i                ),
    .debug_req_i          ( debug_req_i               ),
    .rvfi_probes_o        (                           ), // debug state of the processor, could be used to verify the internal state
    .noc_req_o            ( noc_req_o                 ),
    .noc_resp_i           ( noc_resp_i                )
    ,.csb_valid           ( csb_valid                 )
    ,.csb_ready           ( csb_ready                 )
    ,.csb_addr            ( csb_addr                  )
    ,.csb_wdata           ( csb_wdata                 )
    ,.csb_write           ( csb_write                 )
    ,.csb_nposted         ( csb_nposted               )
    ,.csb_resp_valid      ( csb_resp_valid            )
    ,.csb_resp_data       ( csb_resp_data             )
  );

  // ---------------------------------------------------------------------
  // PMA export: AxCACHE driven from CVA6's own cacheable-region table
  // ---------------------------------------------------------------------
  // The upstream AXI shim emits constant AxCACHE. Re-derive cacheability
  // from this build's CVA6 configuration for each request address.
  function automatic logic [3:0] pma_axcache(input logic [63:0] addr);
    // Cacheable RAM uses AXI Normal/Write-Back; MMIO uses Device.
    return config_pkg::is_inside_cacheable_regions(CVA6Cfg, addr) ? 4'b1111
                                                                  : 4'b0000;
  endfunction

  assign noc_req_ar_cache_o = pma_axcache(noc_req_ar_addr_o);
  assign noc_req_aw_cache_o = pma_axcache(noc_req_aw_addr_o);

  // Debug signals
  // Detect ebreak instruction commit (Breakpoint exception has cause 3)
  assign ebreak_o = i_ariane.i_cva6.commit_stage_i.exception_o.valid &&
                    (i_ariane.i_cva6.commit_stage_i.exception_o.cause == 3);

  // Detect illegal instruction exception commit (Illegal instruction exception has cause 2)
  assign illegal_instr_o = i_ariane.i_cva6.commit_stage_i.exception_o.valid &&
                           (i_ariane.i_cva6.commit_stage_i.exception_o.cause == 2);
  assign program_counter = 64'(i_ariane.i_cva6.commit_stage_i.commit_instr_i[0].pc);


endmodule
