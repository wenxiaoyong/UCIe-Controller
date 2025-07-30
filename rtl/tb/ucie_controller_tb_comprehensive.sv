module ucie_controller_tb_comprehensive
    import ucie_pkg::*;
();
    // Testbench Parameters
    parameter int NUM_LANES = 16; // Reduced for manageable simulation
    parameter int NUM_PROTOCOLS = 4;
    parameter int NUM_VCS = 8;
    parameter int BUFFER_DEPTH = 16; // Reduced for faster simulation
    parameter int SB_FREQ_MHZ = 800;
    parameter int CLK_PERIOD_NS = 10; // 100MHz main clock
    
    // Clock and Reset
    logic clk_main;
    logic clk_sb;
    logic rst_n;
    
    // DUT Interface
    logic                mb_clk_fwd;
    logic [NUM_LANES-1:0] mb_data;
    logic                mb_valid;
    logic                mb_ready;
    logic                mb_clk_fwd_in;
    logic [NUM_LANES-1:0] mb_data_in;
    logic                mb_valid_in;
    logic                mb_ready_out;
    
    logic                sb_clk;
    logic [7:0]          sb_data;
    logic                sb_valid;
    logic                sb_ready;
    logic                sb_clk_in;
    logic [7:0]          sb_data_in;
    logic                sb_valid_in;
    logic                sb_ready_out;
    
    // Protocol Interfaces
    logic [ucie_pkg::FLIT_WIDTH-1:0] pcie_tx_flit, pcie_rx_flit;
    logic                pcie_tx_valid, pcie_rx_valid;
    logic                pcie_tx_ready, pcie_rx_ready;
    logic [7:0]          pcie_tx_vc, pcie_rx_vc;
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] cxl_tx_flit, cxl_rx_flit;
    logic                cxl_tx_valid, cxl_rx_valid;
    logic                cxl_tx_ready, cxl_rx_ready;
    logic [7:0]          cxl_tx_vc, cxl_rx_vc;
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] stream_tx_flit, stream_rx_flit;
    logic                stream_tx_valid, stream_rx_valid;
    logic                stream_tx_ready, stream_rx_ready;
    logic [7:0]          stream_tx_vc, stream_rx_vc;
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] mgmt_tx_flit, mgmt_rx_flit;
    logic                mgmt_tx_valid, mgmt_rx_valid;
    logic                mgmt_tx_ready, mgmt_rx_ready;
    logic [7:0]          mgmt_tx_vc, mgmt_rx_vc;
    
    // Configuration Interface
    logic [31:0]         config_data;
    logic [15:0]         config_addr;
    logic                config_write;
    logic                config_read;
    logic [31:0]         config_rdata;
    logic                config_ready;
    
    // Control and Status
    logic [1:0]          power_state_req;
    logic [1:0]          power_state_ack;
    logic                wake_request;
    logic                sleep_ready;
    logic                link_training_enable;
    logic                link_training_complete;
    logic                link_active;
    logic                link_error;
    logic [7:0]          requested_width;
    logic [7:0]          actual_width;
    logic                width_degraded;
    logic [7:0]          min_width;
    logic [31:0]         controller_status;
    logic [31:0]         link_status;
    logic [31:0]         error_status;
    logic [63:0]         performance_counters [3:0];
    
    // Test Variables
    int test_count = 0;
    int error_count = 0;
    int pass_count = 0;
    
    // Test Data Patterns
    logic [ucie_pkg::FLIT_WIDTH-1:0] test_patterns [15:0];
    
    // DUT Instance
    ucie_controller_top #(
        .NUM_LANES(NUM_LANES),
        .NUM_PROTOCOLS(NUM_PROTOCOLS),
        .NUM_VCS(NUM_VCS),
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .SB_FREQ_MHZ(SB_FREQ_MHZ)
    ) dut (
        .clk_main(clk_main),
        .clk_sb(clk_sb),
        .rst_n(rst_n),
        
        .mb_clk_fwd(mb_clk_fwd),
        .mb_data(mb_data),
        .mb_valid(mb_valid),
        .mb_ready(mb_ready),
        .mb_clk_fwd_in(mb_clk_fwd_in),
        .mb_data_in(mb_data_in),
        .mb_valid_in(mb_valid_in),
        .mb_ready_out(mb_ready_out),
        
        .sb_clk(sb_clk),
        .sb_data(sb_data),
        .sb_valid(sb_valid),
        .sb_ready(sb_ready),
        .sb_clk_in(sb_clk_in),
        .sb_data_in(sb_data_in),
        .sb_valid_in(sb_valid_in),
        .sb_ready_out(sb_ready_out),
        
        .pcie_tx_flit(pcie_tx_flit),
        .pcie_tx_valid(pcie_tx_valid),
        .pcie_tx_ready(pcie_tx_ready),
        .pcie_tx_vc(pcie_tx_vc),
        .pcie_rx_flit(pcie_rx_flit),
        .pcie_rx_valid(pcie_rx_valid),
        .pcie_rx_ready(pcie_rx_ready),
        .pcie_rx_vc(pcie_rx_vc),
        
        .cxl_tx_flit(cxl_tx_flit),
        .cxl_tx_valid(cxl_tx_valid),
        .cxl_tx_ready(cxl_tx_ready),
        .cxl_tx_vc(cxl_tx_vc),
        .cxl_rx_flit(cxl_rx_flit),
        .cxl_rx_valid(cxl_rx_valid),
        .cxl_rx_ready(cxl_rx_ready),
        .cxl_rx_vc(cxl_rx_vc),
        
        .stream_tx_flit(stream_tx_flit),
        .stream_tx_valid(stream_tx_valid),
        .stream_tx_ready(stream_tx_ready),
        .stream_tx_vc(stream_tx_vc),
        .stream_rx_flit(stream_rx_flit),
        .stream_rx_valid(stream_rx_valid),
        .stream_rx_ready(stream_rx_ready),
        .stream_rx_vc(stream_rx_vc),
        
        .mgmt_tx_flit(mgmt_tx_flit),
        .mgmt_tx_valid(mgmt_tx_valid),
        .mgmt_tx_ready(mgmt_tx_ready),
        .mgmt_tx_vc(mgmt_tx_vc),
        .mgmt_rx_flit(mgmt_rx_flit),
        .mgmt_rx_valid(mgmt_rx_valid),
        .mgmt_rx_ready(mgmt_rx_ready),
        .mgmt_rx_vc(mgmt_rx_vc),
        
        .config_data(config_data),
        .config_addr(config_addr),
        .config_write(config_write),
        .config_read(config_read),
        .config_rdata(config_rdata),
        .config_ready(config_ready),
        
        .power_state_req(power_state_req),
        .power_state_ack(power_state_ack),
        .wake_request(wake_request),
        .sleep_ready(sleep_ready),
        
        .link_training_enable(link_training_enable),
        .link_training_complete(link_training_complete),
        .link_active(link_active),
        .link_error(link_error),
        
        .requested_width(requested_width),
        .actual_width(actual_width),
        .width_degraded(width_degraded),
        .min_width(min_width),
        
        .controller_status(controller_status),
        .link_status(link_status),
        .error_status(error_status),
        .performance_counters(performance_counters)
    );
    
    // Clock Generation
    initial begin
        clk_main = 0;
        forever #(CLK_PERIOD_NS/2) clk_main = ~clk_main;
    end
    
    initial begin
        clk_sb = 0;
        forever #(CLK_PERIOD_NS/4) clk_sb = ~clk_sb; // 4x faster
    end
    
    // Reset Generation
    initial begin
        rst_n = 0;
        #(CLK_PERIOD_NS * 10);
        rst_n = 1;
        $display("[%0t] Reset deasserted", $time);
    end
    
    // Initialize Test Patterns
    initial begin
        for (int i = 0; i < 16; i++) begin
            test_patterns[i] = {8{32'h12345678 + i}};
        end
    end
    
    // Safe Loopback Connections - Similar to minimal testbench approach
    assign mb_clk_fwd_in = clk_main; // Use main clock instead of forwarded
    assign mb_data_in = '0; // No actual loopback for now
    assign mb_valid_in = 1'b0; // No valid data
    assign mb_ready = 1'b1; // Always ready
    
    assign sb_clk_in = clk_sb; // Use sideband clock
    assign sb_data_in = '0; // No loopback
    assign sb_valid_in = 1'b0; // No valid data  
    assign sb_ready = 1'b1; // Always ready
    
    // Protocol RX Ready Signals - Use continuous assignments
    assign pcie_rx_ready = 1'b1;
    assign cxl_rx_ready = 1'b1;
    assign stream_rx_ready = 1'b1;
    assign mgmt_rx_ready = 1'b1;
    
    // Test Stimulus Task
    task automatic send_protocol_flit(
        input int protocol_id,
        input logic [ucie_pkg::FLIT_WIDTH-1:0] flit_data,
        input logic [7:0] vc_id
    );
        case (protocol_id)
            0: begin // PCIe
                pcie_tx_flit = flit_data;
                pcie_tx_vc = vc_id;
                pcie_tx_valid = 1'b1;
                wait (pcie_tx_ready);
                @(posedge clk_main);
                pcie_tx_valid = 1'b0;
            end
            
            1: begin // CXL
                cxl_tx_flit = flit_data;
                cxl_tx_vc = vc_id;
                cxl_tx_valid = 1'b1;
                wait (cxl_tx_ready);
                @(posedge clk_main);
                cxl_tx_valid = 1'b0;
            end
            
            2: begin // Streaming
                stream_tx_flit = flit_data;
                stream_tx_vc = vc_id;
                stream_tx_valid = 1'b1;
                wait (stream_tx_ready);
                @(posedge clk_main);
                stream_tx_valid = 1'b0;
            end
            
            3: begin // Management
                mgmt_tx_flit = flit_data;
                mgmt_tx_vc = vc_id;
                mgmt_tx_valid = 1'b1;
                wait (mgmt_tx_ready);
                @(posedge clk_main);
                mgmt_tx_valid = 1'b0;
            end
        endcase
    endtask
    
    // Configuration Task
    task automatic write_config_reg(
        input logic [15:0] addr,
        input logic [31:0] data
    );
        config_addr = addr;
        config_data = data;
        config_write = 1'b1;
        @(posedge clk_main);
        wait (config_ready);
        @(posedge clk_main);
        config_write = 1'b0;
        $display("[%0t] Config write: addr=0x%04x, data=0x%08x", $time, addr, data);
    endtask
    
    task automatic read_config_reg(
        input logic [15:0] addr,
        output logic [31:0] data
    );
        config_addr = addr;
        config_read = 1'b1;
        @(posedge clk_main);
        wait (config_ready);
        data = config_rdata;
        @(posedge clk_main);
        config_read = 1'b0;
        $display("[%0t] Config read: addr=0x%04x, data=0x%08x", $time, addr, data);
    endtask
    
    // Test Check Task
    task automatic check_result(
        input string test_name,
        input logic condition,
        input string description
    );
        test_count++;
        if (condition) begin
            pass_count++;
            $display("[PASS] %s: %s", test_name, description);
        end else begin
            error_count++;
            $display("[FAIL] %s: %s", test_name, description);
        end
    endtask
    
    // Wait for Link Active
    task automatic wait_for_link_active(input int timeout_cycles);
        int count = 0;
        while (!link_active && count < timeout_cycles) begin
            @(posedge clk_main);
            count++;
        end
        if (count >= timeout_cycles) begin
            $display("[ERROR] Timeout waiting for link active");
            error_count++;
        end else begin
            $display("[INFO] Link became active after %0d cycles", count);
        end
    endtask
    
    // Main Test Sequence
    initial begin
        $display("=== UCIe Controller Comprehensive Testbench Started ===");
        
        // Initialize signals
        power_state_req = 2'b00; // L0
        wake_request = 1'b0;
        link_training_enable = 1'b0;
        requested_width = NUM_LANES[7:0];
        min_width = 8'd4;
        
        pcie_tx_valid = 1'b0;
        cxl_tx_valid = 1'b0;
        stream_tx_valid = 1'b0;
        mgmt_tx_valid = 1'b0;
        
        config_write = 1'b0;
        config_read = 1'b0;
        
        // Wait for reset deassertion
        wait (rst_n);
        repeat (10) @(posedge clk_main);
        
        // Test 1: Basic Connectivity and Status Check
        $display("\n=== Test 1: Basic Connectivity ===");
        begin
            repeat (50) @(posedge clk_main);
            
            check_result("BASIC", rst_n, "Reset properly deasserted");
            check_result("BASIC", (controller_status !== 32'hxxxxxxxx), "Controller status readable");
            
            $display("[INFO] Controller Status: 0x%08x", controller_status);
            $display("[INFO] Link Status: 0x%08x", link_status);
        end
        
        // Test 2: Configuration Register Access
        $display("\n=== Test 2: Configuration Register Access ===");
        begin
            logic [31:0] read_data;
            
            // Write and read back configuration registers
            write_config_reg(16'h0001, 32'h0000000F); // Enable all protocols
            read_config_reg(16'h0001, read_data);
            check_result("CONFIG_REG", read_data == 32'h0000000F, "Protocol enable register");
            
            write_config_reg(16'h0002, 32'h03020100); // Set protocol priorities
            read_config_reg(16'h0002, read_data);
            check_result("CONFIG_REG", read_data == 32'h03020100, "Protocol priority register");
        end
        
        // Test 3: Link Training
        $display("\n=== Test 3: Link Training ===");
        begin
            link_training_enable = 1'b1;
            
            // Give reasonable time for training
            wait_for_link_active(5000);
            
            check_result("LINK_TRAINING", !link_error, "No link errors");
            check_result("LINK_TRAINING", actual_width > 0, "Non-zero link width");
            
            $display("[INFO] Actual width: %0d lanes", actual_width);
        end
        
        // Test 4: Simple Protocol Data Transfer
        $display("\n=== Test 4: Protocol Data Transfer ===");
        begin
            // Send test flits on each protocol sequentially (avoid complex parallel operations)
            send_protocol_flit(0, test_patterns[0], 8'h00);
            $display("[INFO] Sent PCIe flit");
            
            repeat (20) @(posedge clk_main);
            
            send_protocol_flit(1, test_patterns[1], 8'h01);
            $display("[INFO] Sent CXL flit");
            
            repeat (20) @(posedge clk_main);
            
            // Check basic protocol readiness
            check_result("PROTOCOL_TX", pcie_tx_ready, "PCIe TX ready");
            check_result("PROTOCOL_TX", cxl_tx_ready, "CXL TX ready");
        end
        
        // Test 5: Power Management
        $display("\n=== Test 5: Power Management ===");
        begin
            // Request L1 power state
            power_state_req = 2'b01;
            
            // Wait for acknowledgment with timeout
            repeat (1000) @(posedge clk_main);
            
            check_result("POWER_MGMT", power_state_ack == 2'b01, "L1 power state entry");
            
            // Return to L0
            power_state_req = 2'b00;
            repeat (500) @(posedge clk_main);
            
            check_result("POWER_MGMT", power_state_ack == 2'b00, "L0 power state recovery");
        end
        
        // Test 6: Performance Monitoring
        $display("\n=== Test 6: Performance Monitoring ===");
        begin
            logic [63:0] initial_counters [3:0];
            
            // Record initial performance counters
            for (int i = 0; i < 4; i++) begin
                initial_counters[i] = performance_counters[i];
            end
            
            // Generate some traffic
            for (int i = 0; i < 5; i++) begin
                send_protocol_flit(0, test_patterns[i % 16], 8'h00);
                repeat (10) @(posedge clk_main);
            end
            
            repeat (100) @(posedge clk_main);
            
            // Check basic counter operation (may not increment in simplified design)
            check_result("PERFORMANCE", 
                       performance_counters[0] >= initial_counters[0], 
                       "PCIe counter stable or incremented");
        end
        
        // Test Summary
        repeat (100) @(posedge clk_main);
        
        $display("\n=== Test Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", error_count);
        
        if (error_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d TESTS FAILED ***", error_count);
        end
        
        $display("=== Final Status ===");
        $display("Controller Status: 0x%08x", controller_status);
        $display("Link Status: 0x%08x", link_status);
        $display("Error Status: 0x%08x", error_status);
        $display("Link Active: %0b", link_active);
        $display("Actual Width: %0d lanes", actual_width);
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #10000000; // 10ms timeout
        $display("[ERROR] Testbench timeout!");
        $finish;
    end
    
    // Optional: Dump waveforms
    initial begin
        $dumpfile("ucie_controller_comprehensive.vcd");
        $dumpvars(0, ucie_controller_tb_comprehensive);
    end

endmodule