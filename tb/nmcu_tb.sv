//********************************************************************************
// Function: Testbench for the NMCU, comparing a traditional vs. accelerated
//           Fully Connected (FC) Layer operation during inference.
//
// Description:
//   This testbench models the core computation of a neural network's
//   fully connected layer:
//
//      Output_Logits = Input_Activations * Weight_Matrix
//
//   It runs two scenarios to demonstrate the NMCU's performance benefit:
//   1. Traditional CPU Model: The CPU issues individual LOAD/STORE operations
//      for every data element, simulating a memory bottleneck.
//   2. NMCU-Accelerated Model: The CPU issues a single INSTR_MATMUL instruction,
//      offloading the entire computation to the NMCU.
//
//   The test measures and compares the cycle counts for both scenarios.
//
// Revision: v3.1 - Corrected SystemVerilog syntax for Verilator
//********************************************************************************
`timescale 1ns / 1ps

module nmcu_tb;

    import nmcu_pkg::*;
    import instr_pkg::*;

    // --- FC Layer Test Parameters ---
    // C[BATCH_SIZE][OUTPUT_NEURONS] = A[BATCH_SIZE][INPUT_FEATURES] * B[INPUT_FEATURES][OUTPUT_NEURONS]
    localparam TIMEOUT_CYCLES    = 5000000; // Increased for traditional test

    // --- Testbench Control ---
    localparam bit PRINT_MATRICES = (BATCH_SIZE * INPUT_FEATURES * OUTPUT_NEURONS < 512);

    // --- Define memory layout ---
    localparam ADDR_INPUTS_BASE  = 'h0000;
    localparam ADDR_WEIGHTS_BASE = 'h1000;
    localparam ADDR_OUTPUTS_BASE = 'h2000;


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
    // B: Layer Weights
    weight_matrix_t fc_weights;
    // C: DUT Output
    output_matrix_t dut_outputs;
    // C: Golden Reference Output
    output_matrix_t golden_outputs;

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
        // 1. Initialization
        initialize_sim();

        // 2. Prepare shared data for both tests
        initialize_fc_data();
        calculate_golden_result();

        // 3. Run the baseline test (Traditional CPU-centric approach)
        run_traditional_cpu_test();
        // 4. Run the accelerated test (NMCU hardware offload)
        run_nmcu_accelerated_test();

        // 5. Compare results and finish simulation
        summarize_performance();
        $display("T=%0t [%m] Simulation finished successfully.", $time);
        $finish;
    end

    //----------------------------------------------------------------
    // Test Tasks
    //----------------------------------------------------------------

    // *****************************************************************
    // NEW: Task to model the traditional CPU-centric approach
    // *****************************************************************
    task automatic run_traditional_cpu_test();
        int error_count = 0;
        longint start_time, end_time;
        psu_type accumulator;
        data_type val_a, val_b;

        $display("");
        $display("T=%0t [%m] ================================================================", $time);
        $display("T=%0t [%m]  SCENARIO 1: Traditional CPU-Centric Matrix Multiplication  ", $time);
        $display("T=%0t [%m]  (CPU issues individual LOAD/STOREs for every operation)     ", $time);
        $display("T=%0t [%m] ================================================================", $time);

        // 1. Load the initial matrices into the NMCU's memory (this is common setup)
        load_matrices_to_nmcu();

        // 2. Perform the matrix multiplication using individual LOADs and STOREs
        $display("T=%0t [%m] ====== Performing MatMul via CPU LOAD/STORE loop ======", $time);
        start_time = $time;
        for (int i = 0; i < BATCH_SIZE; i = i + 1) begin
            for (int j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                accumulator = 0; // Reset accumulator for each output element
                for (int k = 0; k < INPUT_FEATURES; k = k + 1) begin
                    // CPU must fetch one element from Matrix A
                    send_instr(INSTR_LOAD, ADDR_INPUTS_BASE + (i * INPUT_FEATURES + k), '0, '0, '0, 1, '0, '0, '0);
                    wait_for_response();
                    val_a = received_data;

                    // CPU must fetch one element from Matrix B
                    send_instr(INSTR_LOAD, ADDR_WEIGHTS_BASE + (k * OUTPUT_NEURONS + j), '0, '0, '0, 1, '0, '0, '0);
                    wait_for_response();
                    val_b = received_data;

                    // CPU performs the multiply-accumulate operation
                    accumulator += val_a * val_b;
                end
                // CPU must store the final calculated result back to memory
                send_instr(INSTR_STORE, ADDR_OUTPUTS_BASE + (i * OUTPUT_NEURONS + j), '0, '0, accumulator, 1, '0, '0, '0);
                wait_for_response();
            end
        end
        end_time = $time;
        traditional_cycles = (end_time - start_time) / 10;
        $display("T=%0t [%m] INFO: Traditional CPU operation complete.", $time);
        $display("T=%0t [%m] >>>>> PERFORMANCE: Traditional approach took %0d cycles. <<<<<", $time, traditional_cycles);

        // 3. Verify the results (optional for this path, but good for sanity check)
        error_count = verify_results();
        if (error_count > 0) begin
            $display("T=%0t [%m] ****** TRADITIONAL TEST FAILED with %0d errors! ******", $time, error_count);
        end else begin
            $display("T=%0t [%m] ****** TRADITIONAL TEST PASSED! ******", $time);
        end
    endtask


    // *****************************************************************
    // RENAMED: Task for the NMCU-accelerated approach
    // *****************************************************************
    task automatic run_nmcu_accelerated_test();
        int error_count = 0;
        longint matmul_start_time, matmul_end_time;
        $display("");
        $display("T=%0t [%m] ================================================================", $time);
        $display("T=%0t [%m]  SCENARIO 2: NMCU-Accelerated Matrix Multiplication         ", $time);
        $display("T=%0t [%m]  (CPU issues a single MATMUL instruction to offload work)   ", $time);
        $display("T=%0t [%m]  Layer Dimensions: BATCH_SIZE=%0d, IN_FEAT=%0d, OUT_NEURONS=%0d", $time, BATCH_SIZE, INPUT_FEATURES, OUTPUT_NEURONS);
        $display("T=%0t [%m] ================================================================", $time);

        // 1. Load the input and weight matrices into the NMCU's memory
        load_matrices_to_nmcu();

        // 2. Send the single MATMUL instruction and MEASURE PERFORMANCE
        $display("T=%0t [%m] ====== Performing Matrix Multiplication via NMCU ======", $time);
        matmul_start_time = $time;
        send_instr(INSTR_MATMUL, ADDR_INPUTS_BASE, ADDR_WEIGHTS_BASE, ADDR_OUTPUTS_BASE, '0, '0, BATCH_SIZE, OUTPUT_NEURONS, INPUT_FEATURES);
        wait_for_response();
        matmul_end_time = $time;
        if (received_status != 2'b00) begin
             $fatal(1, "T=%0t [%m] FATAL: MATMUL operation FAILED. Status: %b", $time, received_status);
        end
        nmcu_cycles = (matmul_end_time - matmul_start_time) / 10;
        $display("T=%0t [%m] INFO: NMCU MATMUL operation complete.", $time);
        $display("T=%0t [%m] >>>>> PERFORMANCE: NMCU-accelerated approach took %0d cycles. <<<<<", $time, nmcu_cycles);

        // 3. Read back the results from the NMCU and verify against the golden model
        error_count = verify_results();

        // 4. Display results and summary
        if (PRINT_MATRICES) begin
            print_input_matrix("Input Activations (A)", fc_inputs);
            print_weight_matrix("Weights (B)", fc_weights);
            print_output_matrix("Golden Output (C)", golden_outputs);
            print_output_matrix("DUT Output (C)", dut_outputs);
        end
        if (error_count == 0) begin
            $display("T=%0t [%m] ****** NMCU TEST PASSED! ******", $time);
        end else begin
            $display("T=%0t [%m] ****** NMCU TEST FAILED with %0d errors! ******", $time, error_count);
        end
    endtask

    // *****************************************************************
    // NEW: Final performance summary task
    // *****************************************************************
    task automatic summarize_performance();
        real speedup;
        $display("");
        $display("T=%0t [%m] //==============================================================\\", $time);
        $display("T=%0t [%m] ||                  PERFORMANCE COMPARISON SUMMARY                ||", $time);
        $display("T=%0t [%m] \\==============================================================//", $time);
        $display("T=%0t [%m]   Layer Dimensions: BATCH_SIZE=%0d, IN_FEAT=%0d, OUT_NEURONS=%0d", $time, BATCH_SIZE, INPUT_FEATURES, OUTPUT_NEURONS);
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
        $display("T=%0t [%m] ====== Initializing FC Layer Data ======", $time);
        for (int i = 0; i < BATCH_SIZE; i++) begin
            for (int j = 0; j < INPUT_FEATURES; j++) begin
                fc_inputs[i][j] = $urandom_range(0, 15); // Use small numbers for readability
            end
        end
        for (int i = 0; i < INPUT_FEATURES; i++) begin
            for (int j = 0; j < OUTPUT_NEURONS; j++) begin
                fc_weights[i][j] = $urandom_range(0, 15);
            end
        end
    endtask

    task automatic calculate_golden_result();
        $display("T=%0t [%m] ====== Calculating Golden Reference Result ======", $time);
        for (int i = 0; i < BATCH_SIZE; i++) begin
            for (int j = 0; j < OUTPUT_NEURONS; j++) begin
                golden_outputs[i][j] = 0; // Initialize sum
                for (int k = 0; k < INPUT_FEATURES; k++) begin
                    golden_outputs[i][j] += fc_inputs[i][k] * fc_weights[k][j];
                end
            end
        end
    endtask

    task automatic load_matrices_to_nmcu();
        $display("\n T=%0t [%m] ====== Loading Input Matrix (Activations) ======", $time);
        for (int i = 0; i < BATCH_SIZE; i++) begin
            for (int j = 0; j < INPUT_FEATURES; j++) begin
                send_instr(INSTR_STORE, ADDR_INPUTS_BASE + (i * INPUT_FEATURES + j), '0, '0, fc_inputs[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end
        $display("\n T=%0t [%m] ====== Loading Weight Matrix ======", $time);
        for (int i = 0; i < INPUT_FEATURES; i++) begin
            for (int j = 0; j < OUTPUT_NEURONS; j++) begin
                send_instr(INSTR_STORE, ADDR_WEIGHTS_BASE + (i * OUTPUT_NEURONS + j), '0, '0, fc_weights[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end
    endtask

    function int verify_results();
        int errors = 0;
        $display("\n T=%0t [%m] ====== Verifying Results ======", $time);
        for (int i = 0; i < BATCH_SIZE; i = i + 1) begin
            for (int j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                send_instr(INSTR_LOAD, ADDR_OUTPUTS_BASE + (i * OUTPUT_NEURONS + j), '0, '0, '0, 1, '0, '0, '0);
                wait_for_response();
                dut_outputs[i][j] = received_data;
                if (dut_outputs[i][j] != golden_outputs[i][j]) begin
                    $display("T=%0t [%m] FATAL: Result mismatch at C[%0d][%0d]. Expected %0d, got %0d",
                           $time, i, j, golden_outputs[i][j], dut_outputs[i][j]);
                    errors++;
                end else begin
                    $display("T=%0t [%m] INFO: Result at C[%0d][%0d] = %0d (PASSED)",
                            $time, i, j, dut_outputs[i][j]);
                end
            end
        end
        return errors;
    endfunction

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

    logic [PSUM_WIDTH-1:0] received_data;
    logic [1:0]            received_status;
    task automatic wait_for_response();
        int timeout_counter = 0;
        while (!nmcu_resp_valid) begin
            if (timeout_counter > TIMEOUT_CYCLES) begin
                $fatal(1, "T=%0t [%m] FATAL: Timeout waiting for nmcu_resp_valid. DUT did not respond.", $time);
            end
            timeout_counter++;
            @(posedge clk);
        end
        received_data   = nmcu_response.data;
        received_status = nmcu_response.status;
        @(posedge clk);
    endtask

    task automatic print_input_matrix(input string name, input input_matrix_t matrix);
        $display("\n T=%0t [%m] ====== %s [%0d x %0d] ======", $time, name,
                 BATCH_SIZE, INPUT_FEATURES);
        for (int i = 0; i < BATCH_SIZE; i = i + 1) begin
            string row_str = "|";
            for (int j = 0; j < INPUT_FEATURES; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end
    endtask

    task automatic print_weight_matrix(input string name, input weight_matrix_t matrix);
        $display("\n T=%0t [%m] ====== %s [%0d x %0d] ======", $time, name,
                 INPUT_FEATURES, OUTPUT_NEURONS);
        for (int i = 0; i < INPUT_FEATURES; i = i + 1) begin
            string row_str = "|";
            for (int j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end

    endtask

    task automatic print_output_matrix(input string name, input output_matrix_t matrix);
        $display("\n T=%0t [%m] ====== %s [%0d x %0d] ======",
                 $time, name, BATCH_SIZE, OUTPUT_NEURONS);
        for (int i = 0; i < BATCH_SIZE; i = i + 1) begin
            string row_str = "|";
            for (int j = 0; j < OUTPUT_NEURONS; j = j + 1) begin
                row_str = {row_str, $sformatf(" %5d |", matrix[i][j])};
            end
            $display("%s", row_str);
        end
    endtask

endmodule
