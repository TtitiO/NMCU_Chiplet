// nmcu_project/src/control/control_unit_decoder.sv
// Function: This module is the control unit and instruction decoder of the NMCU.
//           It decodes the instruction from the main CPU and sends the appropriate commands to the cache system and PE array.
//           It also handles the response to the main CPU.
//           It is simulated in testbench via `cpu_driver`.
//           In a real system, this would be the UCIe adapter logic. (chiplet_interconnect_if.sv)
//           It is connected to the chiplet interconnect interface. (chiplet_interconnect_if.sv)

// Code structure:
// - Receives instructions from a main CPU.
// - Decodes the instruction.
// - Sends the appropriate commands to the cache system and PE array.
// - Waits for the operation to complete.
// - Sends a response back to the CPU, indicating completion status and returning data if necessary.




`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module control_unit_decoder #(
    parameter DATA_WIDTH  = nmcu_pkg::DATA_WIDTH,
    parameter ADDR_WIDTH  = nmcu_pkg::ADDR_WIDTH,
    parameter LEN_WIDTH   = nmcu_pkg::LEN_WIDTH,
    parameter PSUM_WIDTH  = nmcu_pkg::PSUM_WIDTH
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // From CPU
    input  logic                            cpu_instr_valid,
    input  instr_pkg::instruction_t         cpu_instruction,
    output logic                            cpu_instr_ready,

    // To Cache System (memory requests)
    output nmcu_pkg::mem_req_t              cache_req_o,
    input  nmcu_pkg::mem_resp_t             cache_resp_i,

    // To PE Array Interface
    output logic                            pe_accum_en_o,
    // output instr_pkg::instruction_t         pe_cmd_o, // metadata for PE interface
    output logic                            pe_cmd_valid_o,
    output logic [DATA_WIDTH-1:0]           pe_operand_a_o [3:0],
    output logic [DATA_WIDTH-1:0]           pe_operand_b_o [3:0],
    input  logic                            pe_cmd_ready_i,
    input  logic                            pe_done_i,
    input  logic [PSUM_WIDTH-1:0]           pe_result_i [3:0][3:0],

    // To CPU
    output logic                            nmcu_resp_valid_o,
    input  logic                            nmcu_resp_ready_i,
    output instr_pkg::nmcu_cpu_resp_t       nmcu_response_o
);

    import nmcu_pkg::*;
    import instr_pkg::*;

    typedef enum logic [3:0] {
        IDLE,
        EXECUTE_MEM,
        FETCH_OPERAND_A,
        FETCH_OPERAND_B,
        EXECUTE_PE,
        WAIT_FOR_PE,
        STORE_RESULT,
        RESPOND_CPU
    } cu_state_t;

    cu_state_t current_state, next_state;

    instruction_t current_instruction_reg;
    logic         instruction_valid_reg;
    logic         req_valid_reg;

    logic [DATA_WIDTH-1:0] operand_a_reg, operand_b_reg;
    logic [PSUM_WIDTH-1:0] result_reg;

    // Add a counter for PE execution
    logic [3:0] pe_execution_counter;

    assign cpu_instr_ready = (current_state == IDLE);

    // Instruction buffering (simple)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instruction_valid_reg <= 1'b0;
            current_instruction_reg <= '0;
            operand_a_reg <= '0;
            operand_b_reg <= '0;
            result_reg <= '0;
            current_state <= IDLE;
            req_valid_reg <= 1'b0;
            pe_execution_counter <= '0;
        end else begin
            if (next_state != current_state) begin
                req_valid_reg <= 1'b0;
                if (next_state == EXECUTE_PE) begin
                    pe_execution_counter <= '0;  // Reset counter when entering PE execution
                    $display("T=%0t [CU] Entering EXECUTE_PE: Operands A=%0d, B=%0d", $time, operand_a_reg, operand_b_reg);
                end
            // Set the flag once the request has been asserted.
            end else if (cache_req_o.valid) begin
                req_valid_reg <= 1'b1;
            end
            // Only latch new instruction when in IDLE state and instruction is valid
            if (current_state == IDLE && cpu_instr_valid && cpu_instr_ready) begin
                instruction_valid_reg <= 1'b1;
                current_instruction_reg <= cpu_instruction;
            end else if (current_state == IDLE && next_state != IDLE) begin
                // Clear instruction valid when leaving IDLE state
                instruction_valid_reg <= 1'b0;
            end

            if(current_state == FETCH_OPERAND_A && cache_resp_i.valid && req_valid_reg) begin
                operand_a_reg <= cache_resp_i.rdata;
                $display("T=%0t [CU] FETCH_OPERAND_A: Received operand - data=%0d", $time, cache_resp_i.rdata);
            end

            if(current_state == FETCH_OPERAND_B && cache_resp_i.valid && req_valid_reg) begin
                operand_b_reg <= cache_resp_i.rdata;
                $display("T=%0t [CU] FETCH_OPERAND_B: Received operand - data=%0d", $time, cache_resp_i.rdata);
            end

            if (current_state == EXECUTE_PE) begin
                pe_execution_counter <= pe_execution_counter + 1;
                $display("T=%0t [CU] EXECUTE_PE: Counter=%0d", $time, pe_execution_counter);
            end

            if (current_state == WAIT_FOR_PE && pe_done_i) begin
                result_reg <= pe_result_i[0][0];
                $display("T=%0t [CU] WAIT_FOR_PE: Latched PE result - data=%0d", $time, pe_result_i[0][0]);
            end
        end
    end

    // State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;

        // Default outputs
        cache_req_o       = '0;
        pe_cmd_valid_o    = 1'b0;
        // pe_cmd_o          = '0;
        nmcu_resp_valid_o = 1'b0;
        nmcu_response_o = '0;
        pe_accum_en_o     = 1'b0;
        pe_operand_a_o    = '{default: '0};
        pe_operand_b_o    = '{default: '0};

        unique case (current_state)
            IDLE: begin
                if (instruction_valid_reg) begin
                    case (current_instruction_reg.opcode)
                        INSTR_LOAD, INSTR_STORE: begin
                            // $display("T=%0t [CU] IDLE: Received %s instruction", $time,
                            //        current_instruction_reg.opcode == INSTR_STORE ? "STORE" : "LOAD");
                            next_state = EXECUTE_MEM;
                        end
                        INSTR_MAC: next_state = FETCH_OPERAND_A;
                        INSTR_NOP:  next_state = RESPOND_CPU;
                        default: next_state = RESPOND_CPU; // HALT or error
                    endcase
                end
            end
            EXECUTE_MEM: begin
                // Only assert valid if we haven't received a response yet
                cache_req_o.valid = !req_valid_reg;
                cache_req_o.addr = current_instruction_reg.addr_a;
                cache_req_o.len = current_instruction_reg.len;
                cache_req_o.write_en = (current_instruction_reg.opcode == INSTR_STORE);
                cache_req_o.wdata = current_instruction_reg.data;

                if (cache_resp_i.valid && req_valid_reg) begin
                    next_state = RESPOND_CPU;
                end else begin
                    next_state = EXECUTE_MEM;
                end
            end
            EXECUTE_PE: begin
                pe_cmd_valid_o = (pe_execution_counter == 1);
                // pe_cmd_o       = current_instruction_reg;
                pe_accum_en_o  = 1'b1;
                pe_operand_a_o[0] = operand_a_reg;
                pe_operand_b_o[0] = operand_b_reg;

                if (pe_execution_counter == 4) begin
                    next_state = WAIT_FOR_PE;
                end
            end
            WAIT_FOR_PE: begin
                if (pe_done_i) begin
                    next_state = STORE_RESULT;
                end
            end
            STORE_RESULT: begin
                cache_req_o.valid = !req_valid_reg;
                cache_req_o.addr = current_instruction_reg.addr_c;
                cache_req_o.len = current_instruction_reg.len;
                cache_req_o.write_en = 1'b1;
                cache_req_o.wdata    = result_reg[DATA_WIDTH-1:0]; // Truncate to write to memory

                if (cache_resp_i.valid && req_valid_reg) begin
                    next_state = RESPOND_CPU;
                end
            end
            RESPOND_CPU: begin
                nmcu_resp_valid_o = 1'b1;
                nmcu_response_o.valid = 1'b1;

                case(current_instruction_reg.opcode)
                    INSTR_LOAD: begin
                        nmcu_response_o.data = cache_resp_i.rdata;
                        // $display("T=%0t [CU] RESPOND_CPU: LOAD response - data=%0d",
                        //         $time, cache_resp_i.rdata);
                    end
                    INSTR_STORE: begin
                        // $display("T=%0t [CU] RESPOND_CPU: STORE response - status=%b",
                        //         $time, nmcu_response_o.status);
                    end
                    default:    nmcu_response_o.data = '0;
                endcase
                nmcu_response_o.status = (current_instruction_reg.opcode == INSTR_HALT) ? 2'b01 : 2'b00;

                if (nmcu_resp_ready_i) begin
                    // $display("T=%0t [CU] RESPOND_CPU: Response accepted - moving to IDLE", $time);
                    next_state = IDLE;
                end
            end
            FETCH_OPERAND_A: begin
                // Issue a read request for the first operand (using addr_a from the instruction)
                cache_req_o.valid    = !req_valid_reg;
                cache_req_o.write_en = 1'b0;
                cache_req_o.addr     = current_instruction_reg.addr_a;
                cache_req_o.len      = current_instruction_reg.len;

                if (cache_resp_i.valid && req_valid_reg) begin
                    next_state = FETCH_OPERAND_B;
                end else begin
                    next_state = FETCH_OPERAND_A;
                end
            end
            FETCH_OPERAND_B: begin
                // Issue a read request for the second operand (using addr_b from the instruction)
                cache_req_o.valid    = !req_valid_reg;
                cache_req_o.write_en = 1'b0;
                cache_req_o.addr     = current_instruction_reg.addr_b;
                cache_req_o.len      = current_instruction_reg.len;

                if (cache_resp_i.valid && req_valid_reg) begin
                    next_state = EXECUTE_PE;
                end else begin
                    next_state = FETCH_OPERAND_B;
                end
            end
        endcase
    end

endmodule : control_unit_decoder
