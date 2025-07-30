module ucie_controller_tb_minimal
    import ucie_pkg::*;
();
    // Minimal testbench to isolate convergence issues
    parameter int NUM_LANES = 8; // Reduced for debugging
    parameter int NUM_PROTOCOLS = 4; // Must match protocol layer design  
    parameter int NUM_VCS = 8; // Must match design expectations
    parameter int BUFFER_DEPTH = 8; // Reduced for debugging
    parameter int SB_FREQ_MHZ = 800;
    parameter int CLK_PERIOD_NS = 10; // 100MHz main clock
    
    // Clock and Reset
    logic clk_main;
    logic clk_sb;
    logic rst_n;
    
    // Minimal DUT Interface
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
    
    // Minimal Protocol Interfaces (PCIe only)
    logic [ucie_pkg::FLIT_WIDTH-1:0] pcie_tx_flit, pcie_rx_flit;
    logic                pcie_tx_valid, pcie_rx_valid;
    logic                pcie_tx_ready, pcie_rx_ready;
    logic [7:0]          pcie_tx_vc, pcie_rx_vc;
    
    // Stub other protocols with zero
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
    
    // Initialize all signals to avoid X states
    initial begin
        // Initialize all inputs to known values
        rst_n = 0;
        
        mb_clk_fwd_in = 0;
        mb_data_in = '0;
        mb_valid_in = 0;
        mb_ready = 0;
        
        sb_clk_in = 0;
        sb_data_in = '0;
        sb_valid_in = 0;
        sb_ready = 0;
        
        pcie_tx_flit = '0;
        pcie_tx_valid = 0;
        pcie_rx_ready = 1; // Ready to receive
        pcie_tx_vc = '0;
        
        cxl_tx_flit = '0;
        cxl_tx_valid = 0;
        cxl_rx_ready = 1;
        cxl_tx_vc = '0;
        
        stream_tx_flit = '0;
        stream_tx_valid = 0;
        stream_rx_ready = 1;
        stream_tx_vc = '0;
        
        mgmt_tx_flit = '0;
        mgmt_tx_valid = 0;
        mgmt_rx_ready = 1;
        mgmt_tx_vc = '0;
        
        config_data = '0;
        config_addr = '0;
        config_write = 0;
        config_read = 0;
        
        power_state_req = 2'b00; // L0
        wake_request = 0;
        link_training_enable = 0;
        requested_width = 8'd8; // Match NUM_LANES
        min_width = 8'd4;
        
        // Reset sequence
        repeat (10) @(posedge clk_main);
        rst_n = 1;
        $display("[%0t] Reset deasserted", $time);
        
        // Wait and observe basic operation
        repeat (100) @(posedge clk_main);
        
        $display("[%0t] Basic test completed", $time);
        $display("Controller Status: 0x%08x", controller_status);
        $display("Link Status: 0x%08x", link_status);
        $display("Link Active: %0b", link_active);
        
        $finish;
    end
    
    // Timeout watchdog  
    initial begin
        #1000000; // 1ms timeout
        $display("[ERROR] Testbench timeout!");
        $finish;
    end
    
    // Minimal loopback - static assignments only
    assign mb_clk_fwd_in = clk_main; // Use main clock instead of forwarded
    assign mb_data_in = '0; // No loopback for now
    assign mb_valid_in = 1'b0; // No valid data
    assign mb_ready = 1'b1; // Always ready
    
    assign sb_clk_in = clk_sb; // Use sideband clock
    assign sb_data_in = '0; // No loopback
    assign sb_valid_in = 1'b0; // No valid data  
    assign sb_ready = 1'b1; // Always ready

endmodule
