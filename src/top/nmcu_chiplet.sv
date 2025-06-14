// nmcu_chiplet.sv
// Top level module for NMCU Chiplet
`include "parameters.sv"
`include "types.sv"

module nmcu_chiplet (
    input  logic                    clk,
    input  logic                    rst_n,

    // UCIe Interconnect Interface
    ucie_interface.slave           ucie_if,

    // Memory Interface (to HBM/DDR/SRAM)
    mem_interface.master           mem_if,

    // Status and Debug
    output logic [31:0]            status_reg,
    output logic                   ready,
    output logic                   error
);

    // Internal interconnect signals
    ctrl_cmd_t                     ctrl_cmd;
    logic                          ctrl_cmd_valid;
    logic                          ctrl_cmd_ready;

    cache_req_t                    cache_req;
    logic                          cache_req_valid;
    logic                          cache_req_ready;

    cache_resp_t                   cache_resp;
    logic                          cache_resp_valid;
    logic                          cache_resp_ready;

    pe_data_t                      pe_data;
    logic                          pe_data_valid;
    logic                          pe_data_ready;

    pe_result_t                    pe_result;
    logic                          pe_result_valid;
    logic                          pe_result_ready;

    // UCIe Adapter
    ucie_adapter u_ucie_adapter (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .ucie_if                   (ucie_if),
        .ctrl_cmd                  (ctrl_cmd),
        .ctrl_cmd_valid            (ctrl_cmd_valid),
        .ctrl_cmd_ready            (ctrl_cmd_ready),
        .pe_result                 (pe_result),
        .pe_result_valid           (pe_result_valid),
        .pe_result_ready           (pe_result_ready)
    );

    // Control Unit
    control_unit u_control_unit (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .ctrl_cmd                  (ctrl_cmd),
        .ctrl_cmd_valid            (ctrl_cmd_valid),
        .ctrl_cmd_ready            (ctrl_cmd_ready),
        .cache_req                 (cache_req),
        .cache_req_valid           (cache_req_valid),
        .cache_req_ready           (cache_req_ready),
        .cache_resp                (cache_resp),
        .cache_resp_valid          (cache_resp_valid),
        .cache_resp_ready          (cache_resp_ready),
        .pe_data                   (pe_data),
        .pe_data_valid             (pe_data_valid),
        .pe_data_ready             (pe_data_ready),
        .status_reg                (status_reg),
        .ready                     (ready),
        .error                     (error)
    );

    // Cache System
    cache_memory u_cache_memory (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .cache_req                 (cache_req),
        .cache_req_valid           (cache_req_valid),
        .cache_req_ready           (cache_req_ready),
        .cache_resp                (cache_resp),
        .cache_resp_valid          (cache_resp_valid),
        .cache_resp_ready          (cache_resp_ready),
        .mem_if                    (mem_if)
    );

    // PE Array Interface
    pe_interface u_pe_interface (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .pe_data                   (pe_data),
        .pe_data_valid             (pe_data_valid),
        .pe_data_ready             (pe_data_ready),
        .pe_result                 (pe_result),
        .pe_result_valid           (pe_result_valid),
        .pe_result_ready           (pe_result_ready)
    );

endmodule