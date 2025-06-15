// nmcu_project/src/mem_ctrl/memory_interface.sv
// Function: Simplified behavioral model of an external memory (HBM/DDR).
// TODO: This is a placeholder for a real memory interface.
`include "nmcu_pkg.sv"

module memory_interface #(
    parameter DATA_WIDTH     = nmcu_pkg::DATA_WIDTH,
    parameter ADDR_WIDTH     = nmcu_pkg::ADDR_WIDTH,
    parameter MEM_SIZE_WORDS = nmcu_pkg::MEM_SIZE_WORDS,
    parameter LATENCY        = nmcu_pkg::MEM_LATENCY
) (
    input  logic                clk,
    input  logic                rst_n,
    input  nmcu_pkg::mem_req_t  req_i,
    output nmcu_pkg::mem_resp_t resp_o
);

    // Simulate a simple RAM
    logic [DATA_WIDTH-1:0] mem [0:MEM_SIZE_WORDS-1];

    // Latency pipe for read data
    logic [LATENCY-1:0]           rvalid_pipe;
    logic [DATA_WIDTH-1:0]        rdata_pipe [0:LATENCY-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             rvalid_pipe <= '0;
        end else begin
            // Handle requests
            if (req_i.valid) begin
                if (req_i.write_en) begin
                    mem[req_i.addr] <= req_i.wdata;
                end
            end

            // Manage latency pipe
            rvalid_pipe[0] <= req_i.valid && !req_i.write_en;
            rdata_pipe[0]  <= mem[req_i.addr];
            for (int i = 1; i < LATENCY; i++) begin
                rvalid_pipe[i] <= rvalid_pipe[i-1];
                rdata_pipe[i]  <= rdata_pipe[i-1];
            end
        end
    end

    assign resp_o.valid = rvalid_pipe[LATENCY-1];
    assign resp_o.rdata = rdata_pipe[LATENCY-1];

endmodule
