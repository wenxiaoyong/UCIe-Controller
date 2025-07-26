interface ucie_fdi_if #(
    parameter FLIT_WIDTH = 256,
    parameter NUM_VCS = 8
) (
    input logic clk,
    input logic resetn
);
    
    // Transmit Flit Interface
    logic                   pl_flit_valid;
    logic [FLIT_WIDTH-1:0]  pl_flit_data;
    logic                   pl_flit_sop;
    logic                   pl_flit_eop;
    logic [3:0]            pl_flit_be;
    logic                   lp_flit_ready;
    
    // Receive Flit Interface  
    logic                   lp_flit_valid;
    logic [FLIT_WIDTH-1:0]  lp_flit_data;
    logic                   lp_flit_sop;
    logic                   lp_flit_eop;
    logic [3:0]            lp_flit_be;
    logic                   pl_flit_ready;
    
    // Flit Cancel (256B mode only)
    logic                   pl_flit_cancel;
    
    // Credit Interface
    logic [NUM_VCS-1:0]     pl_credit_return;
    logic [NUM_VCS-1:0]     lp_credit_return;
    
    // State and Control (same as RDI)
    logic                   link_up;
    logic                   link_error;
    logic [7:0]            link_status;
    
    // Power Management (same as RDI)
    logic                   lp_wake_req;
    logic                   pl_wake_ack;
    logic                   pl_clk_req;
    logic                   lp_clk_ack;
    
    // Rx Active Request/Status
    logic                   lp_rx_active_req;
    logic                   pl_rx_active_sts;
    
    modport device (
        input  clk, resetn,
        output pl_flit_valid, pl_flit_data, pl_flit_sop, pl_flit_eop, pl_flit_be,
               pl_flit_cancel, pl_credit_return, lp_wake_req, lp_clk_ack,
               lp_rx_active_req, lp_flit_ready,
        input  lp_flit_ready, lp_flit_valid, lp_flit_data, lp_flit_sop, lp_flit_eop,
               lp_flit_be, lp_credit_return, pl_wake_ack, pl_clk_req,
               pl_rx_active_sts, link_up, link_error, link_status, pl_flit_ready
    );
endinterface