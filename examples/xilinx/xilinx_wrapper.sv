

module xilinx_wrapper

    import cva5_config::*;
    import cva5_types::*;
    //import l2_config_and_types::*; //haven't decided if i need this yet

    //Parameters: (from LITEX-ABACUS)
    #(
        parameter bit [31:0] RESET_VEC = 0,
        parameter bit [31:0] NON_CACHABLE_L = 32'h80000000,
        parameter bit [31:0] NON_CACHABLE_H = 32'hFFFFFFFF,
        parameter int unsigned NUM_CORES = 1
    )

    //Inputs, Outputs, Interfaces:
    (
        //clock and reset
        input logic clk,
        input logic rst,

        local_memory_interface.master instruction_bram[NUM_CORES-1:0],
        local_memory_interface.master data_bram[NUM_CORES-1:0],

        //(from LITEX-ABACUS)
        //TODO: Figure out how interrupts should work in this configuration
        input logic [NUM_CORES-1:0] meip,
        input logic [NUM_CORES-1:0] seip,
        input logic [NUM_CORES-1:0] mtip,
        input logic [NUM_CORES-1:0] msip,
        input logic [63:0] mtime,

        //(from XILINX)
        // AXI SIGNALS - need these to unwrap the interface for packaging //
        input logic m_axi_arready,
        output logic m_axi_arvalid,
        output logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
        output logic [7:0] m_axi_arlen,
        output logic [2:0] m_axi_arsize,
        output logic [1:0] m_axi_arburst,
        output logic [3:0] m_axi_arcache,
        output logic [5:0] m_axi_arid,

        //read data
        output logic m_axi_rready,
        input logic m_axi_rvalid,
        input logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
        input logic [1:0] m_axi_rresp,
        input logic m_axi_rlast,
        input logic [5:0] m_axi_rid,

        //Write channel
        //write address
        input logic m_axi_awready,
        output logic m_axi_awvalid,
        output logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
        output logic [7:0] m_axi_awlen,
        output logic [2:0] m_axi_awsize,
        output logic [1:0] m_axi_awburst,
        output logic [3:0] m_axi_awcache,
        output logic [5:0] m_axi_awid,

        //write data
        input logic m_axi_wready,
        output logic m_axi_wvalid,
        output logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
        output logic [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
        output logic m_axi_wlast,

        //write response
        output logic m_axi_bready,
        input logic m_axi_bvalid,
        input logic [1:0] m_axi_bresp,
        input logic [5:0] m_axi_bid,

        //ABACUS //(from LITEX-ABACUS)
        output logic [31:0] abacus_instruction,
        output logic abacus_instruction_issued,
        
        output logic abacus_icache_request,
        output logic abacus_icache_miss,
        output logic abacus_icache_line_fill_in_progress,

        output logic abacus_dcache_request,
        output logic abacus_dcache_hit,
        output logic abacus_dcache_line_fill_in_progress,

        output logic abacus_branch_misprediction,
        output logic abacus_ras_misprediction,

        //Issue stage stall determination
        output logic abacus_issue_no_instruction_stat,
        output logic abacus_issue_no_id_stat,
        output logic abacus_issue_flush_stat,
        output logic abacus_unit_busy_stat,
        output logic abacus_issue_operands_not_ready_stat,
        output logic abacus_issue_hold_stat,
        output logic abacus_issue_multi_source_stat

    );

    //(LITEX-ABACUS)
    localparam wb_group_config_t STANDARD_WB_GROUP_CONFIG = '{
        0 : '{0: ALU_ID, default : NON_WRITEBACK_ID},
        1 : '{0: LS_ID, default : NON_WRITEBACK_ID},
        2 : '{0: MUL_ID, 1: DIV_ID, 2: CSR_ID, 3: CUSTOM_ID, default : NON_WRITEBACK_ID},
        default : '{default : NON_WRITEBACK_ID}
    };


    //Unused interfaces
    avalon_interface m_avalon[NUM_CORES-1:0]();
    wishbone_interface dwishbone[NUM_CORES-1:0]();
    wishbone_interface iwishbone[NUM_CORES-1:0]();

    //(LITEX-ABACUS)
    ////Interrupts
    interrupt_t[NUM_CORES-1:0] s_interrupt;
    interrupt_t[NUM_CORES-1:0] m_interrupt;

    //AXI interface
    axi_interface m_axi[NUM_CORES]();
    

    generate for (genvar i = 0; i < NUM_CORES; i++) begin : gen_cores
        localparam cpu_config_t STANDARD_CONFIG_I = '{
            //ISA options
            MODES : MSU,
            INCLUDE_UNIT : '{
                MUL : 1,
                DIV : 1,
                CSR : 1,
                FPU : 0,
                CUSTOM : 0,
                default: '0
            },
            INCLUDE_IFENCE : 1,
            INCLUDE_AMO : 1,
            INCLUDE_CBO : 0,
            //CSR constants
            CSRS : '{
                MACHINE_IMPLEMENTATION_ID : 0,
                CPU_ID : i,
                RESET_VEC : RESET_VEC,
                RESET_TVEC : 32'h00000000,
                MCONFIGPTR : '0,
                INCLUDE_ZICNTR : 1,
                INCLUDE_ZIHPM : 1,
                INCLUDE_SSTC : 1,
                INCLUDE_SMSTATEEN : 1
            },
            //Memory Options
            SQ_DEPTH : 4,
            INCLUDE_FORWARDING_TO_STORES : 1,
            AMO_UNIT : '{
                LR_WAIT : 8,
                RESERVATION_WORDS : 8
            },
            INCLUDE_ICACHE : 1,
            ICACHE_ADDR : '{
                L : 32'h00000000,
                H : 32'h7FFFFFFF
            },
            ICACHE : '{
                LINES : 512,
                LINE_W : 8,
                WAYS : 2,
                USE_EXTERNAL_INVALIDATIONS : 1,
                USE_NON_CACHEABLE : 0,
                NON_CACHEABLE : '{
                    L: NON_CACHABLE_L,
                    H: NON_CACHABLE_H
                }
            },
            ITLB : '{
                WAYS : 2,
                DEPTH : 64
            },
            INCLUDE_DCACHE : 1,
            DCACHE_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            DCACHE : '{
                LINES : 512,
                LINE_W : 8,
                WAYS : 2,
                USE_EXTERNAL_INVALIDATIONS : 1,
                USE_NON_CACHEABLE : 1,
                NON_CACHEABLE : '{
                    L: NON_CACHABLE_L,
                    H: NON_CACHABLE_H
                }
            },
            DTLB : '{
                WAYS : 2,
                DEPTH : 64
            },
            //NOTE: This disables instruction BRAM config
            INCLUDE_ILOCAL_MEM : 0,
            ILOCAL_MEM_ADDR : '{
                L : 32'h80000000,
                H : 32'h8FFFFFFF
            },
            //NOTE: This disables data BRAM config
            INCLUDE_DLOCAL_MEM : 0,
            DLOCAL_MEM_ADDR : '{
                L : 32'h80000000,
                H : 32'h8FFFFFFF
            },
            INCLUDE_IBUS : 0,
            IBUS_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            INCLUDE_PERIPHERAL_BUS : 0,
            PERIPHERAL_BUS_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            PERIPHERAL_BUS_TYPE : WISHBONE_BUS,
            //Branch Predictor Options
            INCLUDE_BRANCH_PREDICTOR : 1,
            BP : '{
                WAYS : 2,
                ENTRIES : 512,
                RAS_ENTRIES : 8
            },
            //Writeback Options
            NUM_WB_GROUPS : 3,
            WB_GROUP : STANDARD_WB_GROUP_CONFIG
        };
        .instruction_bram(instruction_bram[i]),
            .data_bram(data_bram[i]),
            .m_axi(m_axi[i]),
            .m_avalon(m_avalon[i]),
            .dwishbone(dwishbone[i]),
            .iwishbone(iwishbone[i]),
            .mtime(mtime),
            .s_interrupt(s_interrupt[i]),
            .m_interrupt(m_interrupt[i]),

            //ABACUS
            .abacus_instruction_issued(abacus_instruction_issued),
            .abacus_instruction(abacus_instruction),
            
            .abacus_icache_request(abacus_icache_request),
            .abacus_icache_miss(abacus_icache_miss),
            .abacus_icache_line_fill_in_progress(abacus_icache_line_fill_in_progress),

            .abacus_dcache_request(abacus_dcache_request),
            .abacus_dcache_hit(abacus_dcache_hit),
            .abacus_dcache_line_fill_in_progress(abacus_dcache_line_fill_in_progress),

            .abacus_branch_misprediction(abacus_branch_misprediction),
            .abacus_ras_misprediction(abacus_ras_misprediction),
            
            .abacus_issue_no_instruction_stat(abacus_issue_no_instruction_stat),
            .abacus_issue_no_id_stat(abacus_issue_no_id_stat),
            .abacus_issue_flush_stat(abacus_issue_flush_stat),
            .abacus_unit_busy_stat(abacus_unit_busy_stat),
            .abacus_issue_operands_not_ready_stat(abacus_issue_operands_not_ready_stat),
            .abacus_issue_hold_stat(abacus_issue_hold_stat),
            .abacus_issue_multi_source_stat(abacus_issue_multi_source_stat),
        .*);
    end endgenerate


    //(XILINX)
    assign m_axi_arready = m_axi.arready;
    assign m_axi_arvalid = m_axi.arvalid;
    assign m_axi_araddr = m_axi.araddr;
    assign m_axi_arlen = m_axi.arlen;
    assign m_axi_arsize = m_axi.arsize;
    assign m_axi_arburst = m_axi.arburst;
    assign m_axi_arcache = m_axi.arcache;
    //assign m_axi_arid = m_axi.arid;

    assign m_axi_rready = m_axi.rready;
    assign m_axi_rvalid = m_axi.rvalid;
    assign m_axi_rdata = m_axi.rdata;
    assign m_axi_rresp = m_axi.rresp;
    assign m_axi_rlast = m_axi.rlast;
    //assign m_axi_rid = m_axi.rid;

    assign m_axi_awready = m_axi.awready;
    assign m_axi_awvalid = m_axi.awvalid;
    assign m_axi_awaddr = m_axi.awaddr;
    assign m_axi_awlen = m_axi.awlen;
    assign m_axi_awsize = m_axi.awsize;
    assign m_axi_awburst = m_axi.awburst;
    assign m_axi_awcache = m_axi.awcache;
    //assign m_axi_awid = m_axi.awid;

    //write data
    assign m_axi_wready = m_axi.wready;
    assign m_axi_wvalid = m_axi.wvalid;
    assign m_axi_wdata = m_axi.wdata;
    assign m_axi_wstrb = m_axi.wstrb;
    assign m_axi_wlast = m_axi.wlast;

    //write response
    assign m_axi_bready = m_axi.bready;
    assign m_axi_bvalid = m_axi.bvalid;
    assign m_axi_bresp = m_axi.bresp;
    //assign m_axi_bid = m_axi.bid;


endmodule


