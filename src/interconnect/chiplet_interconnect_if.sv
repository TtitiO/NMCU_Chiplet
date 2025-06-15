// nmcu_project/src/interconnect/chiplet_interconnect_if.sv
// Function: This module is a placeholder for the chiplet interconnect interface.
//           Its port are connected to the top level of the NMCU. It is simulated in testbench via `cpu_driver`.
//           In a real system, this would be the UCIe adapter logic.
//           For now, we'll connect `cpu_instr_ready` and `nmcu_resp_ready` directly through.
//           The main CPU sends instructions to the NMCU via the chiplet interconnect.
//           The NMCU responds to the main CPU via the chiplet interconnect.

`include "instr_pkg.sv"
module chiplet_interconnect_if (
    input logic clk,
    input logic rst_n,

    // Interface from main CPU (simplified instruction stream)
    input  logic                            cpu_instr_valid,
    output logic                            cpu_instr_ready, // NMCU ready to accept new instruction
    input  instr_pkg::instruction_t         cpu_instruction,

    // Interface to main CPU (NMCU response)
    output logic                            nmcu_resp_valid,
    input  logic                            nmcu_resp_ready, // CPU ready to accept response
    output instr_pkg::nmcu_cpu_resp_t       nmcu_response
);
    // This module is a placeholder. In a real system, this would be the UCIe adapter logic.
    // For now, we'll connect cpu_instr_ready and nmcu_resp_ready directly through.

    // Acknowledge instruction acceptance (simple handshaking)
    assign cpu_instr_ready = 1'b1; // Always ready to accept for simplification

    // Drive response validity (will be connected from internal logic)
    // nmcu_resp_valid is driven from within nmcu.sv
    // nmcu_response is driven from within nmcu.sv

endmodule : chiplet_interconnect_if
