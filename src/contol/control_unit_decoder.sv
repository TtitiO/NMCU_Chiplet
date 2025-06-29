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
    parameter PSUM_WIDTH  = nmcu_pkg::PSUM_WIDTH,
    parameter PE_ROWS     = nmcu_pkg::PE_ROWS,
    parameter PE_COLS     = nmcu_pkg::PE_COLS
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
    output logic [PE_ROWS-1:0]              pe_accum_en_o,
    output logic                            pe_cmd_valid_o,
    output logic [DATA_WIDTH-1:0]           pe_operand_a_o [PE_ROWS-1:0],
    output logic [DATA_WIDTH-1:0]           pe_operand_b_o [PE_COLS-1:0],
    input  logic                            pe_cmd_ready_i,
    input  logic                            pe_done_i,
    input  logic [PSUM_WIDTH-1:0]           pe_result_i [PE_ROWS-1:0][PE_COLS-1:0],

    // To CPU
    output logic                            nmcu_resp_valid_o,
    input  logic                            nmcu_resp_ready_i,
    output instr_pkg::nmcu_cpu_resp_t       nmcu_response_o
);

    import nmcu_pkg::*;
    import instr_pkg::*;


    typedef enum logic [3:0] {
        IDLE,
        // Memory operations (LOAD/STORE)
        EXECUTE_MEM,
        // Matrix Multiplication (MATMUL)
        INIT_MATMUL,        // Initialize counters and addresses for MATMUL
        FETCH_A_TILE,       // Fetch a tile of matrix A
        FETCH_B_TILE,       // Fetch a tile of matrix B
        STREAM_PE_DATA,     // Stream A and B elements to PEs
        // WAIT_FOR_PE_FLUSH,   // New state to wait for systolic array pipeline to drain
        LATCH_PE_RESULTS,   // Latch results from PEs
        UPDATE_TILE_ADDRS,  // Move to the next tile (increment k_tile) or next output block (i_tile, j_tile)
        STORE_C_TILE,       // Store the computed C tile
        // Shared states
        RESPOND_CPU
    } cu_state_t;

    // State registers
    cu_state_t              current_state;
    instruction_t           current_instruction_reg;
    logic                   instruction_valid_reg;
    logic [LEN_WIDTH-1:0]   N_reg, M_reg, K_reg;
    logic [ADDR_WIDTH-1:0]  base_addr_a_reg, base_addr_b_reg, base_addr_c_reg;
    logic [LEN_WIDTH-1:0]   i_tile, j_tile, k_tile;
    logic [LEN_WIDTH-1:0]   fetch_counter;
    logic [LEN_WIDTH-1:0]   stream_counter;
    logic [LEN_WIDTH-1:0]   flush_counter;
    logic                   cache_req_outstanding;
    logic [DATA_WIDTH-1:0]  pe_a_tile_buffer [PE_ROWS-1:0][PE_COLS-1:0];
    logic [DATA_WIDTH-1:0]  pe_b_tile_buffer [PE_ROWS-1:0][PE_COLS-1:0];
    logic [PSUM_WIDTH-1:0]  pe_result_buffer [PE_ROWS-1:0][PE_COLS-1:0];
    logic [DATA_WIDTH-1:0]  cache_rdata_buffer;

    // Next-state logic variables
    cu_state_t              next_state;
    instruction_t           current_instruction_reg_next;
    logic                   instruction_valid_reg_next;
    logic [LEN_WIDTH-1:0]   N_reg_next, M_reg_next, K_reg_next;
    logic [ADDR_WIDTH-1:0]  base_addr_a_reg_next, base_addr_b_reg_next, base_addr_c_reg_next;
    logic [LEN_WIDTH-1:0]   i_tile_next, j_tile_next, k_tile_next;
    logic [LEN_WIDTH-1:0]   fetch_counter_next;
    logic [LEN_WIDTH-1:0]   stream_counter_next;
    logic [LEN_WIDTH-1:0]   flush_counter_next;
    logic                   cache_req_outstanding_next;
    logic [DATA_WIDTH-1:0]  pe_a_tile_buffer_next [PE_ROWS-1:0][PE_COLS-1:0];
    logic [DATA_WIDTH-1:0]  pe_b_tile_buffer_next [PE_ROWS-1:0][PE_COLS-1:0];
    logic [PSUM_WIDTH-1:0]  pe_result_buffer_next [PE_ROWS-1:0][PE_COLS-1:0];
    logic [DATA_WIDTH-1:0]  cache_rdata_buffer_next;


    assign cpu_instr_ready = (current_state == IDLE);

    // --- Data Path Registers Update ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instruction_valid_reg <= 1'b0;
            current_instruction_reg <= '0;
            N_reg <= '0; M_reg <= '0; K_reg <= '0;
            base_addr_a_reg <= '0; base_addr_b_reg <= '0; base_addr_c_reg <= '0;
            i_tile <= '0; j_tile <= '0; k_tile <= '0;
            cache_req_outstanding <= 1'b0;
            pe_a_tile_buffer <= '{default: '{default: '0}};
            pe_b_tile_buffer <= '{default: '{default: '0}};
            pe_result_buffer <= '{default: '{default: '0}};
            cache_rdata_buffer <= '0;
            current_state <= IDLE;
            fetch_counter <= '0;
            stream_counter <= '0;
            flush_counter <= '0;
        end else begin
            current_state <= next_state;
            instruction_valid_reg <= instruction_valid_reg_next;
            current_instruction_reg <= current_instruction_reg_next;
            N_reg <= N_reg_next;
            M_reg <= M_reg_next;
            K_reg <= K_reg_next;
            base_addr_a_reg <= base_addr_a_reg_next;
            base_addr_b_reg <= base_addr_b_reg_next;
            base_addr_c_reg <= base_addr_c_reg_next;
            i_tile <= i_tile_next;
            j_tile <= j_tile_next;
            k_tile <= k_tile_next;
            cache_req_outstanding <= cache_req_outstanding_next;
            pe_a_tile_buffer <= pe_a_tile_buffer_next;
            pe_b_tile_buffer <= pe_b_tile_buffer_next;
            pe_result_buffer <= pe_result_buffer_next;
            cache_rdata_buffer <= cache_rdata_buffer_next;
            fetch_counter <= fetch_counter_next;
            stream_counter <= stream_counter_next;
            flush_counter <= flush_counter_next;

            // --- Logging Logic ---
            // Log when MATMUL is initialized
            if (current_state == INIT_MATMUL && next_state == FETCH_A_TILE) begin
                $display("T=%0t [CU] INIT_MATMUL: Initializing tile counters.", $time);
            end

            // Log when data is latched from memory
            if (cache_resp_i.valid && cache_req_outstanding) begin
                if (current_state == FETCH_A_TILE) begin
                    $display("T=%0t [CU] FETCH_A_TILE: Buffered A[%0d][%0d] = %0d", $time, fetch_counter / PE_COLS, fetch_counter % PE_COLS, cache_resp_i.rdata);
                end
                if (current_state == FETCH_B_TILE) begin
                    $display("T=%0t [CU] FETCH_B_TILE: Buffered B[%0d][%0d] = %0d", $time, fetch_counter / PE_COLS, fetch_counter % PE_COLS, cache_resp_i.rdata);
                end
            end

            // Log when PEs accept the data
            if(current_state == STREAM_PE_DATA && pe_cmd_ready_i) begin
                $display("T=%0t [CU] STREAM_PE_DATA: PE array accepted data.", $time);
                for (int i = 0; i < PE_ROWS; i++) begin
                    $display("T=%0t [CU] STREAM_PE_DATA: A[%0d] = %0d", $time, i, pe_operand_a_o[i]);
                end
                for (int j = 0; j < PE_COLS; j++) begin
                    $display("T=%0t [CU] STREAM_PE_DATA: B[%0d] = %0d", $time, j, pe_operand_b_o[j]);
                end
            end

            // Log when the PE array signals it's done
            if (current_state == LATCH_PE_RESULTS) begin
                $display("T=%0t [CU] LATCH_PE_RESULTS: PE array done, results buffered.", $time);
            end



            // Log when the final response is sent back to the CPU
            if (current_state == RESPOND_CPU && nmcu_resp_ready_i) begin
                 case(current_instruction_reg.opcode)
                    INSTR_LOAD:
                        $display("T=%0t [CU] RESPOND_CPU: LOAD response - data=%0d", $time, cache_rdata_buffer);
                    INSTR_MATMUL: 
                        $display("T=%0t [CU] RESPOND_CPU: MATMUL complete.", $time);
                    default: 
                        $display("T=%0t [CU] RESPOND_CPU: Instruction completed, moving to IDLE", $time);
                endcase
            end
        end
    end

    // --- Combinational Logic for Next State and Outputs ---
    always_comb begin
        logic [LEN_WIDTH-1:0] row;
        logic [LEN_WIDTH-1:0] col;

        // Default assignments
        next_state = current_state;
        current_instruction_reg_next = current_instruction_reg;
        instruction_valid_reg_next = instruction_valid_reg;
        N_reg_next = N_reg;
        M_reg_next = M_reg;
        K_reg_next = K_reg;
        base_addr_a_reg_next = base_addr_a_reg;
        base_addr_b_reg_next = base_addr_b_reg;
        base_addr_c_reg_next = base_addr_c_reg;
        i_tile_next = i_tile;
        j_tile_next = j_tile;
        k_tile_next = k_tile;
        cache_req_outstanding_next = cache_req_outstanding;
        pe_a_tile_buffer_next = pe_a_tile_buffer;
        pe_b_tile_buffer_next = pe_b_tile_buffer;
        pe_result_buffer_next = pe_result_buffer;
        cache_rdata_buffer_next = cache_rdata_buffer;
        fetch_counter_next = fetch_counter;
        stream_counter_next = stream_counter;
        flush_counter_next = flush_counter;

        // Default outputs
        cache_req_o       = '0;
        pe_cmd_valid_o    = 1'b0;
        pe_accum_en_o     = (k_tile == 0) ? '{default: 1'b0} : '{default: 1'b1};
        pe_operand_a_o    = '{default: '0};
        pe_operand_b_o    = '{default: '0};
        nmcu_resp_valid_o = 1'b0;
        nmcu_response_o   = '0;

        // Latch new instruction
        if (current_state == IDLE && cpu_instr_valid && cpu_instr_ready) begin
            instruction_valid_reg_next = 1'b1;
            current_instruction_reg_next = cpu_instruction;
        end

        // De-assert valid latch when moving out of IDLE
        if (current_state == IDLE && next_state != IDLE) begin
            instruction_valid_reg_next = 1'b0;
        end

        // Latch data from cache response
        if (cache_resp_i.valid && cache_req_outstanding) begin
            cache_rdata_buffer_next = cache_resp_i.rdata;
        end

        unique case (current_state)
            IDLE: begin
                if (instruction_valid_reg) begin
                    case (current_instruction_reg.opcode)
                        INSTR_LOAD, INSTR_STORE: begin
                            next_state = EXECUTE_MEM;
                        end
                        INSTR_MATMUL: begin
                            next_state = INIT_MATMUL;
                            N_reg_next = current_instruction_reg.N;
                            M_reg_next = current_instruction_reg.M;
                            K_reg_next = current_instruction_reg.K;
                            base_addr_a_reg_next = current_instruction_reg.addr_a;
                            base_addr_b_reg_next = current_instruction_reg.addr_b;
                            base_addr_c_reg_next = current_instruction_reg.addr_c;
                        end
                        INSTR_NOP:  next_state = RESPOND_CPU;
                        default: next_state = RESPOND_CPU; // HALT or error
                    endcase
                end
            end
            EXECUTE_MEM: begin
                cache_req_o.valid = !cache_req_outstanding;
                cache_req_o.addr = current_instruction_reg.addr_a;
                cache_req_o.len = current_instruction_reg.len;
                cache_req_o.write_en = (current_instruction_reg.opcode == INSTR_STORE);
                cache_req_o.wdata = current_instruction_reg.data;

                if (cache_req_o.valid) begin
                    cache_req_outstanding_next = 1'b1;
                end

                if (cache_resp_i.valid && cache_req_outstanding) begin
                    next_state = RESPOND_CPU;
                    cache_req_outstanding_next = 1'b0;
                end
            end
            INIT_MATMUL: begin
                // Initialize tile counters
                i_tile_next = 0;
                j_tile_next = 0;
                k_tile_next = 0;
                next_state = FETCH_A_TILE; // Start fetching the first tile of A
                fetch_counter_next = 0;
            end
            FETCH_A_TILE: begin
                // Fetch PE_ROWS rows of A, with PE_COLS elements each.
                // For simplicity, this FSM fetches one element at a time.
                // TODO: A more optimized version could use burst reads.
                cache_req_o.valid = !cache_req_outstanding;
                cache_req_o.write_en = 1'b0;
                row = fetch_counter / PE_COLS;
                col = fetch_counter % PE_COLS;
                cache_req_o.addr = base_addr_a_reg + ((i_tile * PE_ROWS + row) * K_reg) + (k_tile * PE_COLS + col);
                cache_req_o.len = PE_ROWS;

                if (cache_req_o.valid) begin
                    cache_req_outstanding_next = 1'b1;
                end

                if (cache_resp_i.valid && cache_req_outstanding) begin
                    pe_a_tile_buffer_next[row][col] = cache_resp_i.rdata;
                    cache_req_outstanding_next = 1'b0;

                    if (fetch_counter == (PE_ROWS * PE_COLS - 1)) begin
                        // Done fetching A tile, now fetch B tile
                        fetch_counter_next = 0;
                        next_state = FETCH_B_TILE;
                    end else begin
                        fetch_counter_next = fetch_counter + 1;
                    end

                end
            end

            FETCH_B_TILE: begin
                // Fetch PE_COLS columns of B, with PE_ROWS elements each.
                cache_req_o.valid = !cache_req_outstanding;
                cache_req_o.write_en = 1'b0;
                row = fetch_counter / PE_COLS; // This is 'k' dimension
                col = fetch_counter % PE_COLS; // This is 'j' dimension
                cache_req_o.addr = base_addr_b_reg + ((k_tile * PE_ROWS + row) * M_reg) + (j_tile * PE_COLS + col);
                cache_req_o.len = PE_COLS;

                if (cache_req_o.valid) begin
                    cache_req_outstanding_next = 1'b1;
                end
                if (cache_resp_i.valid && cache_req_outstanding) begin
                    pe_b_tile_buffer_next[row][col] = cache_resp_i.rdata;
                    cache_req_outstanding_next = 1'b0;
                    if (fetch_counter == (PE_ROWS * PE_COLS - 1)) begin
                        // Done fetching B tile, now stream data to PEs
                        next_state = STREAM_PE_DATA;
                        fetch_counter_next = 0;
                        stream_counter_next = 0;
                    end else begin
                        fetch_counter_next = fetch_counter + 1;
                    end

                end
            end

            STREAM_PE_DATA: begin
                pe_cmd_valid_o = 1'b1; // Signal to PEs that valid data is available
                if (k_tile == 0) begin
                    pe_accum_en_o = (stream_counter == 0) ? '{default: 1'b0} : '{default: 1'b1};
                end else begin
                    pe_accum_en_o = '{default: 1'b1};
                end
                for (int i = 0; i < PE_ROWS; i++) begin
                    int k_idx = stream_counter - i;
                    if (k_idx >= 0 && k_idx < PE_COLS) begin
                        pe_operand_a_o[i] = pe_a_tile_buffer[i][k_idx];
                    end else begin
                        pe_operand_a_o[i] = '0;
                    end
                end
                // Stream B (from top to bottom)
                for (int j = 0; j < PE_COLS; j++) begin
                    int k_idx = stream_counter - j;
                    if (k_idx >= 0 && k_idx < PE_ROWS) begin
                        pe_operand_b_o[j] = pe_b_tile_buffer[k_idx][j];
                    end else begin
                        pe_operand_b_o[j] = '0;
                    end
                end
                if (pe_cmd_ready_i) begin
                    if (stream_counter == (PE_ROWS + PE_COLS - 1)) begin
                         next_state = LATCH_PE_RESULTS;
                    end else begin
                         stream_counter_next = stream_counter + 1;
                    end
                end
            end

            // WAIT_FOR_PE_FLUSH: begin
            //     // Wait for the PE array to signal completion for the current tile computation
            //     if (flush_counter == (PE_ROWS + PE_COLS - 2)) begin
            //         next_state = LATCH_PE_RESULTS;
            //     end else begin
            //         flush_counter_next = flush_counter + 1;
            //     end
            // end

            LATCH_PE_RESULTS: begin
                // Latch the results from the PEs
                if (pe_done_i) begin
                    for (int i = 0; i < PE_ROWS; i++) begin
                        for (int j = 0; j < PE_COLS; j++) begin
                            pe_result_buffer_next[i][j] = pe_result_i[i][j];
                        end
                    end
                    next_state = UPDATE_TILE_ADDRS;
                end
            end

            UPDATE_TILE_ADDRS: begin
                // This logic correctly iterates through the tiles for the entire matrix multiplication.
                k_tile_next = k_tile + 1;
                if (k_tile_next == (K_reg / PE_ROWS)) begin
                    k_tile_next = 0;
                    // We have a final result tile, store it.
                    // This is a simplification; in reality, you would store C and then update j, i.
                    // For clarity, we separate STORE from the main compute loop.
                    fetch_counter_next = 0; // Prepare for store
                    next_state = STORE_C_TILE;
                end else begin
                    // Get next A and B tiles for accumulation
                    fetch_counter_next = 0;
                    next_state = FETCH_A_TILE;
                end
            end


            STORE_C_TILE: begin
                cache_req_o.valid = !cache_req_outstanding;
                cache_req_o.len = 1;
                cache_req_o.write_en = 1'b1;
                row = fetch_counter / PE_COLS;
                col = fetch_counter % PE_COLS;
                cache_req_o.addr = base_addr_c_reg + ((i_tile * PE_ROWS + row) * M_reg) + (j_tile * PE_COLS + col);
                cache_req_o.wdata = pe_result_buffer[row][col][DATA_WIDTH-1:0];

                if (cache_req_o.valid) begin
                    cache_req_outstanding_next = 1'b1;
                end

                if (cache_resp_i.valid && cache_req_outstanding) begin
                    cache_req_outstanding_next = 1'b0;
                    if(fetch_counter == (PE_ROWS * PE_COLS - 1)) begin
                        // Finished storing tile. Move to the next tile in the C matrix.
                        j_tile_next = j_tile + 1;
                        if (j_tile_next == (M_reg / PE_COLS)) begin
                            j_tile_next = 0;
                            i_tile_next = i_tile + 1;
                        end

                        if (i_tile_next == (N_reg / PE_ROWS)) begin
                            // Entire matrix multiplication is complete!
                            next_state = RESPOND_CPU;
                        end else begin
                            // Start calculation for the new C tile
                            k_tile_next = 0; // Reset k
                            fetch_counter_next = 0;
                            next_state = FETCH_A_TILE;
                        end

                    end else begin
                        fetch_counter_next = fetch_counter + 1;
                    end
                end
            end


            RESPOND_CPU: begin
                nmcu_resp_valid_o = 1'b1;
                nmcu_response_o.valid = 1'b1;
                nmcu_response_o.status = (current_instruction_reg.opcode == INSTR_HALT) ? 2'b01 : 2'b00;

                case(current_instruction_reg.opcode)
                    INSTR_LOAD: begin
                        nmcu_response_o.data = cache_rdata_buffer;
                    end
                    INSTR_MATMUL: begin
                         nmcu_response_o.data = '0; // No data returned for MATMUL, just status
                    end
                    default: nmcu_response_o.data = '0;
                endcase

                if (nmcu_resp_ready_i) begin
                    next_state = IDLE;
                    instruction_valid_reg_next = 1'b0;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule : control_unit_decoder
