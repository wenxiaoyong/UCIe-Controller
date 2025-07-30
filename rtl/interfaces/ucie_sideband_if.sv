interface ucie_sideband_if (
    input logic aux_clk,      // Auxiliary clock (always-on)
    input logic aux_resetn    // Auxiliary reset
);
    
    // Physical Sideband Signals
    logic       sb_clk_out;    // 800 MHz sideband clock output
    logic       sb_data_out;   // Sideband data output
    logic       sb_data_in;    // Sideband data input
    
    // Redundant Sideband (Advanced Package only)
    logic       sb_clk_out_red;
    logic       sb_data_out_red;
    logic       sb_data_in_red;
    
    // Sideband Packet Interface
    logic               tx_packet_valid;
    logic [63:0]        tx_packet_data;
    logic [7:0]         tx_packet_length;
    logic [3:0]         tx_packet_type;
    logic               tx_packet_ready;
    
    logic               rx_packet_valid;
    logic [63:0]        rx_packet_data;
    logic [7:0]         rx_packet_length;
    logic [3:0]         rx_packet_type;
    logic               rx_packet_ready;
    
    // Status and Control
    logic               sideband_active;
    logic               sideband_error;
    logic [7:0]         sideband_status;
    
    modport master (
        input  aux_clk, aux_resetn, sb_data_in, sb_data_in_red,
               tx_packet_ready, rx_packet_valid, rx_packet_data,
               rx_packet_length, rx_packet_type,
        output sb_clk_out, sb_data_out, sb_clk_out_red, sb_data_out_red,
               tx_packet_valid, tx_packet_data, tx_packet_length,
               tx_packet_type, rx_packet_ready, sideband_active,
               sideband_error, sideband_status
    );

    modport controller (
        input  aux_clk, aux_resetn, sb_data_in, sb_data_in_red,
               rx_packet_valid, rx_packet_data, rx_packet_length, rx_packet_type,
        output sb_clk_out, sb_data_out, sb_clk_out_red, sb_data_out_red,
               tx_packet_valid, tx_packet_data, tx_packet_length,
               tx_packet_type, rx_packet_ready, tx_packet_ready,
               sideband_active, sideband_error, sideband_status
    );
    
    modport thermal_mgmt (
        input  aux_clk, aux_resetn,
        output tx_packet_valid, tx_packet_data, tx_packet_length, tx_packet_type,
        input  tx_packet_ready, rx_packet_valid, rx_packet_data,
               rx_packet_length, rx_packet_type,
        output rx_packet_ready
    );
endinterface
