interface ucie_rdi_if #(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 16
) (
    input logic clk,
    input logic resetn
);
    
    // Transmit Interface
    logic                   tx_valid;
    logic [DATA_WIDTH-1:0]  tx_data;
    logic [USER_WIDTH-1:0]  tx_user;
    logic                   tx_sop;
    logic                   tx_eop;
    logic [5:0]            tx_empty;
    logic                   tx_ready;
    
    // Receive Interface
    logic                   rx_valid;
    logic [DATA_WIDTH-1:0]  rx_data;
    logic [USER_WIDTH-1:0]  rx_user;
    logic                   rx_sop;
    logic                   rx_eop;
    logic [5:0]            rx_empty;
    logic                   rx_ready;
    
    // State and Control
    logic                   link_up;
    logic                   link_error;
    logic [7:0]            link_status;
    
    // Power Management
    logic                   lp_wake_req;
    logic                   pl_wake_ack;
    logic                   pl_clk_req;
    logic                   lp_clk_ack;
    
    // Stallreq/Ack Mechanism
    logic                   lp_stallreq;
    logic                   pl_stallack;
    logic                   pl_stallreq;
    logic                   lp_stallack;
    
    // State Request/Status
    logic [3:0]            lp_state_req;
    logic [3:0]            pl_state_sts;
    logic [3:0]            pl_state_req;
    logic [3:0]            lp_state_sts;
    
    modport device (
        input  clk, resetn,
        output tx_valid, tx_data, tx_user, tx_sop, tx_eop, tx_empty,
               lp_wake_req, lp_clk_ack, lp_stallreq, lp_stallack,
               lp_state_req, lp_state_sts, rx_ready,
        input  tx_ready, rx_valid, rx_data, rx_user, rx_sop, rx_eop, rx_empty,
               pl_wake_ack, pl_clk_req, pl_stallreq, pl_stallack,
               pl_state_req, pl_state_sts, link_up, link_error, link_status
    );
    
    modport controller (
        input  clk, resetn, tx_valid, tx_data, tx_user, tx_sop, tx_eop, tx_empty,
               lp_wake_req, lp_clk_ack, lp_stallreq, lp_stallack,
               lp_state_req, lp_state_sts, rx_ready,
        output tx_ready, rx_valid, rx_data, rx_user, rx_sop, rx_eop, rx_empty,
               pl_wake_ack, pl_clk_req, pl_stallreq, pl_stallack,
               pl_state_req, pl_state_sts, link_up, link_error, link_status
    );
endinterface