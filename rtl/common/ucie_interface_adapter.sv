module ucie_interface_adapter
    import ucie_pkg::*;
#(
    parameter int NUM_PROTOCOLS = 4,
    parameter int NUM_VCS = 8
) (
    input  logic clk,
    input  logic rst_n,
    
    // RDI/FDI Interface Connections
    ucie_rdi_if.controller rdi,
    ucie_fdi_if.controller fdi,
    
    // Protocol Layer Array Interfaces (Output)
    output logic [FLIT_WIDTH-1:0] ul_tx_flit [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] ul_tx_valid,
    input  logic [NUM_PROTOCOLS-1:0] ul_tx_ready,
    output logic [7:0] ul_tx_vc [NUM_PROTOCOLS-1:0],
    
    input  logic [FLIT_WIDTH-1:0] ul_rx_flit [NUM_PROTOCOLS-1:0],
    input  logic [NUM_PROTOCOLS-1:0] ul_rx_valid,
    output logic [NUM_PROTOCOLS-1:0] ul_rx_ready,
    input  logic [7:0] ul_rx_vc [NUM_PROTOCOLS-1:0],
    
    // Protocol Configuration
    input  logic [NUM_PROTOCOLS-1:0] protocol_enable,
    input  logic [7:0] protocol_priority [NUM_PROTOCOLS-1:0]
);

// Protocol mapping based on RDI/FDI data analysis
logic [3:0] current_protocol_id;
logic [7:0] current_vc;

// Extract protocol information from flit header
flit_header_t fdi_header, rdi_header;
assign fdi_header = extract_flit_header(fdi.pl_flit_data);
assign rdi_header = extract_flit_header({rdi.tx_data[255:0]});

// Protocol ID mapping logic
always_comb begin
    if (fdi.pl_flit_valid) begin
        current_protocol_id = fdi_header.protocol_id;
        current_vc = fdi_header.virtual_channel;
    end else if (rdi.tx_valid) begin
        // For RDI, infer protocol from data patterns or use default
        current_protocol_id = rdi_header.protocol_id;
        current_vc = rdi_header.virtual_channel;
    end else begin
        current_protocol_id = 4'h0; // Default to PCIe
        current_vc = 8'h0;
    end
end

// TX Path: RDI/FDI to Protocol Arrays
genvar i;
generate
    for (i = 0; i < NUM_PROTOCOLS; i++) begin : gen_tx_protocol
        always_comb begin
            if (protocol_enable[i] && (current_protocol_id == i[3:0])) begin
                // Use FDI interface for flit-based protocols  
                if (fdi.pl_flit_valid) begin
                    ul_tx_flit[i] = fdi.pl_flit_data;
                    ul_tx_valid[i] = fdi.pl_flit_valid;
                    ul_tx_vc[i] = current_vc;
                end
                // Use RDI interface for raw data protocols
                else if (rdi.tx_valid) begin
                    ul_tx_flit[i] = rdi.tx_data[FLIT_WIDTH-1:0];
                    ul_tx_valid[i] = rdi.tx_valid;
                    ul_tx_vc[i] = current_vc;
                end else begin
                    ul_tx_flit[i] = '0;
                    ul_tx_valid[i] = 1'b0;
                    ul_tx_vc[i] = 8'h0;
                end
            end else begin
                ul_tx_flit[i] = '0;
                ul_tx_valid[i] = 1'b0;
                ul_tx_vc[i] = 8'h0;
            end
        end
    end
endgenerate

// TX Ready back-pressure
logic combined_tx_ready;
always_comb begin
    combined_tx_ready = 1'b0;
    for (int j = 0; j < NUM_PROTOCOLS; j++) begin
        if (protocol_enable[j] && (current_protocol_id == j[3:0])) begin
            combined_tx_ready = ul_tx_ready[j];
            break;
        end
    end
end

assign fdi.lp_flit_ready = combined_tx_ready;
assign rdi.tx_ready = combined_tx_ready;

// RX Path: Protocol Arrays to RDI/FDI
logic [FLIT_WIDTH-1:0] rx_flit_muxed;
logic rx_valid_muxed;
logic [7:0] rx_vc_muxed;
logic [3:0] rx_protocol_muxed;

// Priority-based arbitration for RX data
always_comb begin
    rx_flit_muxed = '0;
    rx_valid_muxed = 1'b0;
    rx_vc_muxed = 8'h0;
    rx_protocol_muxed = 4'h0;
    
    // Priority arbitration based on protocol_priority
    for (int k = 0; k < NUM_PROTOCOLS; k++) begin
        if (protocol_enable[k] && ul_rx_valid[k]) begin
            rx_flit_muxed = ul_rx_flit[k];
            rx_valid_muxed = ul_rx_valid[k];
            rx_vc_muxed = ul_rx_vc[k];
            rx_protocol_muxed = k[3:0];
            break;
        end
    end
end

// Connect to FDI RX interface
assign fdi.lp_flit_valid = rx_valid_muxed;
assign fdi.lp_flit_data = rx_flit_muxed;
assign fdi.lp_flit_sop = (extract_flit_header(rx_flit_muxed).flit_type == FLIT_HEADER) || 
                         (extract_flit_header(rx_flit_muxed).flit_type == FLIT_SINGLE);
assign fdi.lp_flit_eop = (extract_flit_header(rx_flit_muxed).flit_type == FLIT_TAIL) || 
                         (extract_flit_header(rx_flit_muxed).flit_type == FLIT_SINGLE);
assign fdi.lp_flit_be = 4'hF; // Full byte enable

// Connect to RDI RX interface
assign rdi.rx_valid = rx_valid_muxed;
assign rdi.rx_data = {{(512-FLIT_WIDTH){1'b0}}, rx_flit_muxed}; // Pad to RDI width
assign rdi.rx_sop = fdi.lp_flit_sop;
assign rdi.rx_eop = fdi.lp_flit_eop;
assign rdi.rx_empty = 6'h0;

// RX Ready back-pressure
generate
    for (i = 0; i < NUM_PROTOCOLS; i++) begin : gen_rx_ready
        assign ul_rx_ready[i] = protocol_enable[i] ? (fdi.pl_flit_ready && rdi.rx_ready) : 1'b0;
    end
endgenerate

// Status and control signal pass-through
assign rdi.link_up = |protocol_enable;
assign rdi.link_status = {4'h0, protocol_enable[3:0]};
assign rdi.link_error = 1'b0;

assign fdi.link_up = rdi.link_up;
assign fdi.link_status = rdi.link_status;
assign fdi.link_error = rdi.link_error;

endmodule
