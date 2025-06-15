// nmcu_project/src/chiplets/nmcu.sv
// Function: Top-level module for the NMCU chiplet.
`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module nmcu (
    input  logic                            clk,
    input  logic                            rst_n,

    // Interface to Chiplet Interconnect (simulated by testbench)
    input  logic                            cpu_instr_valid,
    input  instr_pkg::instruction_t         cpu_instruction,
    output logic                            cpu_instr_ready,

    output logic                            nmcu_resp_valid_o,
    input  logic                            nmcu_resp_ready_i,
    output instr_pkg::nmcu_cpu_resp_t       nmcu_response_o
);

    // Internal Wires
    nmcu_pkg::mem_req_t  cu_cache_req;
    nmcu_pkg::mem_resp_t cu_cache_resp;

    nmcu_pkg::mem_req_t  cache_mem_req;
    nmcu_pkg::mem_resp_t cache_mem_resp;

    logic                pe_cmd_valid;
    instr_pkg::instruction_t pe_cmd;
    logic [nmcu_pkg::DATA_WIDTH-1:0] pe_operand_a;
    logic [nmcu_pkg::DATA_WIDTH-1:0] pe_operand_b;
    logic                pe_cmd_ready;
    logic                pe_done;
    logic [nmcu_pkg::DATA_WIDTH-1:0] pe_result;

    // Instantiate Control Unit
    control_unit_decoder cu_inst (
        .clk(clk), .rst_n(rst_n),
        .cpu_instr_valid(cpu_instr_valid),
        .cpu_instruction(cpu_instruction),
        .cpu_instr_ready(cpu_instr_ready),
        .cache_req_o(cu_cache_req),
        .cache_resp_i(cu_cache_resp),
        .pe_cmd_valid_o(pe_cmd_valid),
        .pe_cmd_o(pe_cmd),
        .pe_operand_a_o(pe_operand_a),
        .pe_operand_b_o(pe_operand_b),
        .pe_cmd_ready_i(pe_cmd_ready),
        .pe_done_i(pe_done),
        .pe_result_i(pe_result), // *** Connect new result input
        .nmcu_resp_valid_o(nmcu_resp_valid_o),
        .nmcu_resp_ready_i(nmcu_resp_ready_i),
        .nmcu_response_o(nmcu_response_o)
    );

    // Instantiate PE Array Interface
    pe_array_interface pe_if_inst (
        .clk(clk), .rst_n(rst_n),
        .pe_cmd_valid_i(pe_cmd_valid),
        .pe_cmd_i(pe_cmd),
        .pe_operand_a_i(pe_operand_a),
        .pe_operand_b_i(pe_operand_b),
        .pe_cmd_ready_o(pe_cmd_ready),
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
