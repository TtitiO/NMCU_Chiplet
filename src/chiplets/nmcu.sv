// nmcu_project/src/chiplets/nmcu.sv
// Function: Top-level module for the NMCU chiplet.
`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module nmcu #(
    parameter DATA_WIDTH  = nmcu_pkg::DATA_WIDTH,
    parameter ADDR_WIDTH  = nmcu_pkg::ADDR_WIDTH,
    parameter LEN_WIDTH   = nmcu_pkg::LEN_WIDTH,
    parameter PSUM_WIDTH  = nmcu_pkg::PSUM_WIDTH,
    parameter PE_ROWS     = nmcu_pkg::PE_ROWS,
    parameter PE_COLS     = nmcu_pkg::PE_COLS
    // parameter INPUT_FEATURES = nmcu_pkg::INPUT_FEATURES
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            cpu_instr_valid,
    input  instr_pkg::instruction_t         cpu_instruction,
    output logic                            cpu_instr_ready,
    output logic                            nmcu_resp_valid_o,
    input  logic                            nmcu_resp_ready_i,
    output instr_pkg::nmcu_cpu_resp_t       nmcu_response_o
);

    nmcu_pkg::mem_req_t  cu_cache_req;
    nmcu_pkg::mem_resp_t cu_cache_resp;
    nmcu_pkg::mem_req_t  cache_mem_req;
    nmcu_pkg::mem_resp_t cache_mem_resp;

    // --- Wires for CU <-> PE Interface Connection ---
    logic [PE_ROWS-1:0]               pe_accum_en;
    logic [DATA_WIDTH-1:0]        pe_operand_a [PE_ROWS-1:0];
    logic [DATA_WIDTH-1:0]        pe_operand_b [PE_COLS-1:0];
    logic [PSUM_WIDTH-1:0]        pe_result [PE_ROWS-1:0][PE_COLS-1:0];
    logic                         pe_cmd_valid;
    logic                         pe_cmd_ready;
    logic                         pe_done;

    // Instantiate Control Unit
    control_unit_decoder #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .PE_ROWS(PE_ROWS),
        .PE_COLS(PE_COLS)
    ) cu_inst (
        .clk(clk), .rst_n(rst_n),
        .cpu_instr_valid(cpu_instr_valid),
        .cpu_instruction(cpu_instruction),
        .cpu_instr_ready(cpu_instr_ready),
        .cache_req_o(cu_cache_req),
        .cache_resp_i(cu_cache_resp),
        .pe_accum_en_o(pe_accum_en),
        .pe_operand_a_o(pe_operand_a),
        .pe_operand_b_o(pe_operand_b),
        .pe_cmd_valid_o(pe_cmd_valid),
        .pe_cmd_ready_i(pe_cmd_ready),
        .pe_done_i(pe_done),
        .pe_result_i(pe_result),
        .nmcu_resp_valid_o(nmcu_resp_valid_o),
        .nmcu_resp_ready_i(nmcu_resp_ready_i),
        .nmcu_response_o(nmcu_response_o)
    );

    pe_array_interface #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .PE_ROWS(PE_ROWS),
        .PE_COLS(PE_COLS)
        // .INPUT_FEATURES(nmcu_pkg::INPUT_FEATURES)
    ) pe_if_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pe_cmd_valid_i(pe_cmd_valid),
        .pe_cmd_ready_o(pe_cmd_ready),
        .pe_accum_en_i(pe_accum_en),
        .pe_operand_a_i(pe_operand_a),
        .pe_operand_b_i(pe_operand_b),
        .pe_done_o(pe_done),
        .pe_result_o(pe_result)
    );

    // Instantiate Cache System
    cache_system cache_inst (
        .clk(clk), .rst_n(rst_n),
        .req_i(cu_cache_req),
        .resp_o(cu_cache_resp),
        .mem_req_o(cache_mem_req),
        .mem_resp_i(cache_mem_resp)
    );

    // Instantiate Memory Interface
    memory_interface mem_if_inst (
        .clk(clk), .rst_n(rst_n),
        .req_i(cache_mem_req),
        .resp_o(cache_mem_resp)
    );

    // NOTE: The chiplet_interconnect_if is not instantiated here as its logic
    // is conceptually part of the control_unit_decoder and simulated by the TB.
    // TODO: Add the chiplet_interconnect_if module here.

endmodule
