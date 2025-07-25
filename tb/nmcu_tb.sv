//********************************************************************************
// Function: Testbench for the NMCU, comparing a traditional vs. accelerated
//           two-layer Fully Connected (FC) Inference operation.
//
// Description:
//   This testbench models a two-layer FC operation:
//
//      MatMul -> ReLU -> MatMul
//
//   It runs two scenarios to demonstrate the NMCU's performance benefit:
//   1. Traditional CPU Model: The CPU issues individual LOAD/STORE operations
//      for every data element and performs all calculations (MatMul, ReLU).
//   2. NMCU-Accelerated Model: The CPU issues INSTR_MATMUL instructions
//      to offload the heavy computation and performs the lighter-weight
//      ReLU operations on the results.
//
//   The test measures and compares the total cycle counts for both scenarios.
//
// Revision: v4.0 - Extended to a two-layer FC test (MatMul->ReLU->MatMul->ReLU)
//                  and removed bias addition.
//********************************************************************************
`timescale 1ns / 1ps

module nmcu_tb;

    import nmcu_pkg::*;
    import instr_pkg::*;

    // --- FC Layer Test Parameters ---
    // Layer 1: C1[BATCH_SIZE][OUTPUT_NEURONS] = A[BATCH_SIZE][INPUT_FEATURES] * B1[INPUT_FEATURES][OUTPUT_NEURONS]
    // Layer 2: C2[BATCH_SIZE][OUTPUT_NEURONS] = C1[BATCH_SIZE][OUTPUT_NEURONS] * B2[OUTPUT_NEURONS][OUTPUT_NEURONS]
    localparam int TIMEOUT_CYCLES    = 10000000; // Increased for traditional test

    // --- Testbench Control ---
    localparam bit PrintMatrices = (BATCH_SIZE * INPUT_FEATURES * OUTPUT_NEURONS < 512);


    // --- Define memory layout ---
    localparam logic [ADDR_WIDTH-1:0] ADDR_INPUTS_BASE   = 'h0000; // Input Activations
    localparam logic [ADDR_WIDTH-1:0] ADDR_WEIGHTS1_BASE = 'h1000; // Layer 1 Weights
    localparam logic [ADDR_WIDTH-1:0] ADDR_WEIGHTS2_BASE = 'h3000; // Layer 2 Weights
    localparam logic [ADDR_WIDTH-1:0] ADDR_OUTPUTS1_BASE = 'h4000; // Intermediate Output (After Layer 1)
    localparam logic [ADDR_WIDTH-1:0] ADDR_OUTPUTS2_BASE = 'h5000; // Final Output (After Layer 2)


    // --- Clock and Reset ---
    logic clk;
    logic rst_n;

    // --- DUT Interface ---
    logic                       cpu_instr_valid;
    instr_pkg::instruction_t    cpu_instruction;
    logic                       cpu_instr_ready;
    logic                       nmcu_resp_valid;
    logic                       nmcu_resp_ready;
    instr_pkg::nmcu_cpu_resp_t  nmcu_response;

    // --- FC Layer Data Matrices ---
    // A: Input Activations
    input_matrix_t fc_inputs;
    // B1: Layer 1 Weights
    weight_matrix_t fc_weights1;
    // B2: Layer 2 Weights (Input Features = Output Neurons from Layer 1)
    typedef data_type weight_matrix2_t [OUTPUT_NEURONS][OUTPUT_NEURONS];
    weight_matrix2_t fc_weights2;
    // C1: Intermediate DUT Output
    output_matrix_t dut_outputs1;
    // C2: Final DUT Output
    output_matrix_t dut_outputs2;
    // Golden Reference Outputs
    output_matrix_t golden_outputs1; // Intermediate (after Layer 1)
    output_matrix_t golden_outputs2; // Final (after Layer 2)

    // --- Performance Counters ---
    longint traditional_cycles;
    longint nmcu_cycles;

    // --- Instantiate DUT ---
    nmcu dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_instr_valid(cpu_instr_valid),
        .cpu_instruction(cpu_instruction),
        .cpu_instr_ready(cpu_instr_ready),
        .nmcu_resp_valid_o(nmcu_resp_valid),
        .nmcu_resp_ready_i(nmcu_resp_ready),
        .nmcu_response_o(nmcu_response)
    );

    // --- Clock Generation ---
    always #5 clk = ~clk;

    // *****************************************************************
    // NEW: Updated main execution flow
    // *****************************************************************
    initial begin
        initialize_sim();
        initialize_fc_data();
        calculate_golden_result();
        run_traditional_cpu_test();
        run_nmcu_accelerated_test();
        summarize_performance();
        $display("T=%0t [%m] Simulation finished successfully.", $time);
        $finish;
    end

        // --- Sub-task for Layer 1 ---
    task automatic run_layer1_traditional();
        logic signed [PSUM_WIDTH-1:0] ps_sum;
        data_type val_a, val_b;
        integer i, j, k;
        $display("T=%0t [%m] ====== Performing Layer 1 (MatMul + ReLU) via CPU ======", $time);
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                ps_sum = 0;
                for (k = 0; k < INPUT_FEATURES; k = k + 1) begin
                    send_instr(CACHE_READ, ADDR_INPUTS_BASE + (i * INPUT_FEATURES + k), '0, '0, '0, 1, '0, '0, '0);
                    while (!nmcu_resp_valid) begin
                        @(posedge clk);
                    end
                    val_a = nmcu_response.data;
                    send_instr(CACHE_READ, ADDR_WEIGHTS1_BASE + (k * OUTPUT_NEURONS + j), '0, '0, '0, 1, '0, '0, '0);
                    while (!nmcu_resp_valid) begin
                        @(posedge clk);
                    end
                    val_b = nmcu_response.data;
                    ps_sum += val_a * val_b;
                end
                if (ps_sum < 0) ps_sum = 0;
                send_instr(CACHE_WRITE, ADDR_OUTPUTS1_BASE + (i * OUTPUT_NEURONS + j), '0, '0, data_type'(ps_sum), 1, '0, '0, '0);
                wait_for_response();
            end
        end
    endtask

    // --- Sub-task for Layer 2 ---
    task automatic run_layer2_traditional();
        logic signed [PSUM_WIDTH-1:0] ps_sum;
        data_type val_a, val_b;
        integer i, j, k;
        $display("T=%0t [%m] ====== Performing Layer 2 (MatMul + ReLU) via CPU ======", $time);
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                ps_sum = 0;
                for (k = 0; k < OUTPUT_NEURONS; k = k + 1) begin
                    send_instr(CACHE_READ, ADDR_OUTPUTS1_BASE + (i * OUTPUT_NEURONS + k), '0, '0, '0, 1, '0, '0, '0);
                    wait_for_response();
                    // while (!nmcu_resp_valid) begin
                    //     @(posedge clk);
                    // end
                    val_a = nmcu_response.data;
                    send_instr(CACHE_READ, ADDR_WEIGHTS2_BASE + (k * OUTPUT_NEURONS + j), '0, '0, '0, 1, '0, '0, '0);
                    wait_for_response();
                    // while (!nmcu_resp_valid) begin
                    //     @(posedge clk);
                    // end
                    val_b = nmcu_response.data;
                    ps_sum += val_a * val_b;
                end
                if (ps_sum < 0) ps_sum = 0;
                send_instr(CACHE_WRITE, ADDR_OUTPUTS2_BASE + (i * OUTPUT_NEURONS + j), '0, '0, data_type'(ps_sum), 1, '0, '0, '0);
                wait_for_response();
            end
        end
    endtask

    // --- Main wrapper task for the traditional test ---
    task automatic run_traditional_cpu_test();
        int error_count = 0;
        longint start_time, end_time;

        $display("");
        $display("T=%0t [%m] ================================================================", $time);
        $display("T=%0t [%m]  SCENARIO 1: Traditional CPU-Centric Operation (Refactored)    ", $time);
        $display("T=%0t [%m] ================================================================", $time);
        load_all_data_to_memory();
        start_time = $time;
        run_layer1_traditional();
        run_layer2_traditional();
        end_time = $time;

        traditional_cycles = (end_time - start_time) / 10;
        $display("T=%0t [%m] >>>>> PERFORMANCE: Traditional CPU-centric approach took %0d cycles. <<<<<", $time, traditional_cycles);

        verify_results(error_count);
        if (error_count == 0) begin
            $display("T=%0t [%m] ****** TRADITIONAL CPU TEST PASSED! ******", $time);
        end else begin
            $display("T=%0t [%m] ****** TRADITIONAL CPU TEST FAILED with %0d errors! ******", $time, error_count);
        end
    endtask


    // *****************************************************************
    // RENAMED: Task for the NMCU-accelerated approach
    // *****************************************************************
    task automatic run_nmcu_accelerated_test();
        int error_count = 0;
        longint start_time, end_time;
        logic signed [PSUM_WIDTH-1:0] intermediate_val, final_val;
        data_type bias_val;
        integer i, j;
        $display("");
        $display("T=%0t [%m] ================================================================", $time);
        $display("T=%0t [%m]  SCENARIO 2: NMCU-Accelerated Matrix Multiplication            ", $time);
        $display("T=%0t [%m]  (NMCU for MatMul, CPU for Bias-Add and ReLU)                  ", $time);
        $display("T=%0t [%m]  Layer Dimensions: BATCH_SIZE=%0d, IN_FEAT=%0d, OUT_NEURONS=%0d", $time, BATCH_SIZE, INPUT_FEATURES, OUTPUT_NEURONS);
        $display("T=%0t [%m] ================================================================", $time);

        // 1. Load the input and weight matrices into the NMCU's memory
        load_all_data_to_memory();


        // --- Part 1: Offload Matrix Multiplication to NMCU ---
        // 2. Send the single MATMUL instruction and MEASURE PERFORMANCE
        $display("T=%0t [%m] ====== Performing Layer 1 MatMul via NMCU ======", $time);
        start_time = $time;
        send_instr(INSTR_MATMUL, ADDR_INPUTS_BASE, ADDR_WEIGHTS1_BASE, ADDR_OUTPUTS1_BASE, '0, '0, BATCH_SIZE, OUTPUT_NEURONS, INPUT_FEATURES);
        wait_for_response();
        if (received_status != 2'b00) $fatal(1, "T=%0t [%m] FATAL: MATMUL 1 FAILED. Status: %b", $time, received_status);
        $display("T=%0t [%m] INFO: NMCU MATMUL 1 operation complete.", $time);

        // --- Part 2: CPU performs Bias-Add and ReLU post-processing ---
        $display("T=%0t [%m] ====== Performing Bias-Add and ReLU via CPU ======", $time);
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin

                // CPU fetches the intermediate result from the NMCU
                send_instr(CACHE_READ, ADDR_OUTPUTS1_BASE + (i * OUTPUT_NEURONS + j), '0, '0, '0, 1, '0, '0, '0);
                // wait_for_response();
                while (!nmcu_resp_valid) begin
                    @(posedge clk);
                end
                intermediate_val = nmcu_response.data;
                if (intermediate_val < 0) begin
                    intermediate_val = 0; // ReLU
                end
                // CPU writes the final result back, overwriting the intermediate value
                send_instr(CACHE_WRITE, ADDR_OUTPUTS1_BASE + (i * OUTPUT_NEURONS + j), '0, '0, data_type'(intermediate_val), 1, '0, '0, '0);
                wait_for_response();
            end
        end
        // --- Part 3: Offload Layer 2 MatMul to NMCU ---
        $display("T=%0t [%m] ====== Performing Layer 2 MatMul via NMCU ======", $time);
        send_instr(INSTR_MATMUL, ADDR_OUTPUTS1_BASE, ADDR_WEIGHTS2_BASE, ADDR_OUTPUTS2_BASE, '0, '0, BATCH_SIZE, OUTPUT_NEURONS, OUTPUT_NEURONS);
        while (!nmcu_resp_valid) begin
            @(posedge clk);
        end
        if (received_status != 2'b00) $fatal(1, "T=%0t [%m] FATAL: MATMUL 2 FAILED. Status: %b", $time, received_status);
        $display("T=%0t [%m] INFO: NMCU MATMUL 2 operation complete.", $time);

        end_time = $time;
        nmcu_cycles = (end_time - start_time) / 10;

        $display("T=%0t [%m] INFO: NMCU-accelerated 2-Layer FC operation complete.", $time);
        $display("T=%0t [%m] >>>>> PERFORMANCE: NMCU-accelerated approach took %0d cycles. <<<<<", $time, nmcu_cycles);

        // 4. Read back the final results and verify against the golden model
        verify_results(error_count);

        if (error_count == 0) begin
            $display("T=%0t [%m] ****** NMCU TEST PASSED! ******", $time);
        end else begin
            $display("T=%0t [%m] ****** NMCU TEST FAILED with %0d errors! ******", $time, error_count);
        end

        // 5. Print matrices if enabled
        if (PrintMatrices) begin
            print_input_matrix("Input Activations (A)", fc_inputs);
            print_weight_matrix("Weights 1 (B1)", fc_weights1);
            print_weight2_matrix("Weights 2 (B2)", fc_weights2);
            print_output_matrix("Golden Output (C2)", golden_outputs2);
            print_output_matrix("DUT Output (C2)", dut_outputs2);
        end
    endtask

    // *****************************************************************
    // NEW: Final performance summary task
    // *****************************************************************
    task automatic summarize_performance();
        real speedup;
        $display("");
        $display("T=%0t [%m] //==============================================================\\", $time);
        $display("T=%0t [%m] ||             TWO-LAYER FC PERFORMANCE SUMMARY                ||", $time);
        $display("T=%0t [%m] \\==============================================================//", $time);
        $display("T=%0t [%m]   Operation: Output = ReLU(ReLU(Input*Weights1)*Weights2)", $time);
        $display("T=%0t [%m]   Layer 1 Dim: BATCH=%0d, IN_FEAT=%0d, OUT_NEURONS=%0d", $time, BATCH_SIZE, INPUT_FEATURES, OUTPUT_NEURONS);
        $display("T=%0t [%m]   Layer 2 Dim: BATCH=%0d, IN_FEAT=%0d, OUT_NEURONS=%0d", $time, BATCH_SIZE, OUTPUT_NEURONS, OUTPUT_NEURONS);
        $display("T=%0t [%m] ----------------------------------------------------------------", $time);
        $display("T=%0t [%m]   Traditional CPU-Centric Cycles : %0d", $time, traditional_cycles);
        $display("T=%0t [%m]   NMCU-Accelerated Cycles        : %0d", $time, nmcu_cycles);
        $display("T=%0t [%m] ----------------------------------------------------------------", $time);
        if (nmcu_cycles > 0 && traditional_cycles > 0) begin
            speedup = (real'(traditional_cycles)) / (real'(nmcu_cycles));
            $display("T=%0t [%m]   Speedup Factor: %.2fx", $time, speedup);
        end else begin
            $display("T=%0t [%m]   Speedup Factor: N/A (one of the cycle counts was zero)", $time);
        end
        $display("T=%0t [%m] //==============================================================\\", $time);
    endtask

    task automatic initialize_fc_data();
        integer i, j;
        $display("T=%0t [%m] ====== Initializing FC Layer Data (Inputs, Weights, Bias) ======", $time);
        for (i = 0; i < BATCH_SIZE; i++) begin
            for (j = 0; j < INPUT_FEATURES; j++) begin
                fc_inputs[i][j] = $urandom_range(7, 0);
            end
        end
        for (i = 0; i < INPUT_FEATURES; i++) begin
            for (j = 0; j < OUTPUT_NEURONS; j++) begin
                fc_weights1[i][j] = $urandom_range(7, 0);
            end
        end
        for (i = 0; i < OUTPUT_NEURONS; i++) begin
            for (j = 0; j < OUTPUT_NEURONS; j++) begin
                fc_weights2[i][j] = $urandom_range(7, 0);
            end
        end
    endtask

    task automatic calculate_golden_result();
        logic signed [PSUM_WIDTH-1:0] intermediate_sum;
        integer i, j, k;
        $display("T=%0t [%m] ====== Calculating Golden Reference Result (MatMul + Bias + ReLU) ======", $time);
        for (i = 0; i < BATCH_SIZE; i++) begin
            for (j = 0; j < OUTPUT_NEURONS; j++) begin
                intermediate_sum = 0;
                for (k = 0; k < INPUT_FEATURES; k++) begin
                    intermediate_sum += fc_inputs[i][k] * fc_weights1[k][j];
                end
                golden_outputs1[i][j] = data_type'((intermediate_sum < 0) ? 0 : intermediate_sum);
            end
        end
        for (i = 0; i < BATCH_SIZE; i++) begin
            for (j = 0; j < OUTPUT_NEURONS; j++) begin
                intermediate_sum = 0;
                for (k = 0; k < OUTPUT_NEURONS; k++) begin
                    intermediate_sum += golden_outputs1[i][k] * fc_weights2[k][j];
                end
                golden_outputs2[i][j] = data_type'(intermediate_sum);
            end
        end
    endtask

    task automatic load_all_data_to_memory();
        integer i, j;
        // Load Input Activations
        $display("T=%0t [%m] ====== Loading Input Matrix (Activations) ======", $time);
        for (i = 0; i < BATCH_SIZE; i++) begin
            for (j = 0; j < INPUT_FEATURES; j++) begin
                send_instr(CACHE_WRITE, ADDR_INPUTS_BASE + (i * INPUT_FEATURES + j), '0, '0, fc_inputs[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end
        // Load Weights 1
        $display("T=%0t [%m] ====== Loading Weight Matrix 1 ======", $time);
        for (i = 0; i < INPUT_FEATURES; i++) begin
            for (j = 0; j < OUTPUT_NEURONS; j++) begin
                send_instr(CACHE_WRITE, ADDR_WEIGHTS1_BASE + (i * OUTPUT_NEURONS + j), '0, '0, fc_weights1[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end
        // Load Weights 2
        $display("T=%0t [%m] ====== Loading Weight Matrix 2 ======", $time);
        for (i = 0; i < OUTPUT_NEURONS; i++) begin
            for (j = 0; j < OUTPUT_NEURONS; j++) begin
                send_instr(CACHE_WRITE, ADDR_WEIGHTS2_BASE + (i * OUTPUT_NEURONS + j), '0, '0, fc_weights2[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end
    endtask

    task automatic verify_results(output int errors);
        integer i, j;
        errors = 0;
        $display("");
        $display("T=%0t [%m] ====== Verifying Final Results (from Addr: %h) ======",
                 $time, ADDR_OUTPUTS2_BASE);
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                send_instr(CACHE_READ, ADDR_OUTPUTS2_BASE + (i * OUTPUT_NEURONS + j),
                           '0, '0, '0, 1, '0, '0, '0);
                wait_for_response();
                dut_outputs2[i][j] = received_data;
                if (dut_outputs2[i][j] != golden_outputs2[i][j]) begin
                    $display("T=%0t [%m] FATAL: Result mismatch at C2[%0d][%0d]. Expected %0d, got %0d",
                           $time, i, j, golden_outputs2[i][j], dut_outputs2[i][j]);
                    errors++;
                end else begin
                    $display("T=%0t [%m] INFO: Result at C2[%0d][%0d] = %0d (PASSED)",
                            $time, i, j, dut_outputs2[i][j]);
                end
            end
        end
    endtask

    //----------------------------------------------------------------
    // Utility and Interface Tasks
    //----------------------------------------------------------------

    task automatic initialize_sim();
        clk = 0;
        rst_n = 0;
        cpu_instr_valid = 0;
        cpu_instruction = '0;
        nmcu_resp_ready = 1'b1; // Always ready to accept response
        $display("T=%0t [%m] Starting Simulation...", $time);
        #10;
        rst_n = 1;
        $display("T=%0t [%m] Reset released.", $time);
        repeat(2) @(posedge clk);
    endtask

    task automatic send_instr(
        input opcode_t op,
        input logic [ADDR_WIDTH-1:0] addr_a,
        input logic [ADDR_WIDTH-1:0] addr_b,
        input logic [ADDR_WIDTH-1:0] addr_c,
        input logic [DATA_WIDTH-1:0] data,
        input logic [LEN_WIDTH-1:0]  len,
        input logic [LEN_WIDTH-1:0] N,
        input logic [LEN_WIDTH-1:0] M,
        input logic [LEN_WIDTH-1:0] K
    );
        wait (cpu_instr_ready);
        @(posedge clk);
        cpu_instr_valid = 1;
        cpu_instruction = '{
            opcode: op,
            addr_a: addr_a,
            addr_b: addr_b,
            addr_c: addr_c,
            data:   data,
            len:    len,
            N:      N,
            M:      M,
            K:      K
        };
        @(posedge clk);
        cpu_instr_valid = 0;
    endtask

    logic [DATA_WIDTH-1:0] received_data;
    logic [1:0]            received_status;
    task automatic wait_for_response();
        int timeout_counter = 0;
        int is_x = 0;
        int time_out = 0;
        while (!nmcu_resp_valid) begin
            if ($isunknown(nmcu_resp_valid)) begin
                $fatal(2, "T=%0t [%m] FATAL: nmcu_resp_valid is 'X'. DUT driver bug!", $time);
                is_x = 1;
                break;
            end
            if (timeout_counter > TIMEOUT_CYCLES) begin
                $fatal(1, "T=%0t [%m] FATAL: Timeout waiting for nmcu_resp_valid.", $time);
                time_out = 1;
                break;
            end
            timeout_counter++;
            @(posedge clk);
        end
        if (time_out) begin
            $fatal(1, "T=%0t [%m] FATAL: Timeout waiting for nmcu_resp_valid.", $time);
        end
        if (is_x) begin
            $fatal(2, "T=%0t [%m] FATAL: Received 'X' data from NMCU. Check DUT driver.", $time);
        end
        received_data   = nmcu_response.data;
        received_status = nmcu_response.status;
        @(posedge clk);
    endtask

    task automatic print_input_matrix(input string name, input input_matrix_t matrix);
        integer i, j;
        $display("");
        $display("T=%0t [%m] ====== %s [%0d x %0d] ======", $time, name,
                 BATCH_SIZE, INPUT_FEATURES);
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            string row_str = "|";
            for (j = 0; j < INPUT_FEATURES; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end
    endtask

    task automatic print_weight_matrix(input string name, input weight_matrix_t matrix);
        integer i, j;
        $display("");
        $display("T=%0t [%m] ====== %s [%0d x %0d] ======", $time, name,
                 INPUT_FEATURES, OUTPUT_NEURONS);
        for (i = 0; i < INPUT_FEATURES; i = i + 1) begin
            string row_str = "|";
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end
    endtask

    task automatic print_weight2_matrix(input string name, input weight_matrix2_t matrix);
        integer i, j;
        $display("");
        $display("T=%0t [%m] ====== %s [%0d x %0d] ======", $time, name,
                 OUTPUT_NEURONS, OUTPUT_NEURONS);
        for (i = 0; i < OUTPUT_NEURONS; i = i + 1) begin
            string row_str = "|";
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end
    endtask

    task automatic print_output_matrix(input string name, input output_matrix_t matrix);
        integer i, j;
        $display("");
        $display("T=%0t [%m] ====== %s [%0d x %0d] ======",
                 $time, name, BATCH_SIZE, OUTPUT_NEURONS);
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            string row_str = "|";
            for (j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end
    endtask
    task automatic reset_dut();
        $display("T=%0t [%m] ====== Applying DUT Reset ======", $time);
        rst_n = 1'b0;
        // Keep reset asserted for a few cycles
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        // Add a small delay for signals to stabilize after reset
        #10;
        $display("T=%0t [%m] ====== DUT Reset Released ======", $time);
    endtask

endmodule
