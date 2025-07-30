package ucie_common_pkg;

    // UCIe Common Definitions - Restored and Enhanced
    
    // System-wide Constants
    parameter int SYSTEM_CLOCK_FREQ_HZ = 1000000000;  // 1 GHz base clock
    parameter int SIDEBAND_CLOCK_FREQ_HZ = 800000000; // 800 MHz sideband
    
    // Common Width Definitions
    parameter int BYTE_WIDTH = 8;
    parameter int WORD_WIDTH = 32;
    parameter int DWORD_WIDTH = 64;
    parameter int FLIT_WIDTH = 256;
    parameter int CACHE_LINE_WIDTH = 512;
    
    // Common Type Definitions
    typedef logic [7:0]   byte_t;
    typedef logic [15:0]  word16_t;
    typedef logic [31:0]  word32_t;
    typedef logic [63:0]  word64_t;
    typedef logic [127:0] word128_t;
    typedef logic [255:0] word256_t;
    typedef logic [511:0] word512_t;
    
    // Address and ID Types
    typedef logic [63:0] address_t;
    typedef logic [15:0] transaction_id_t;
    typedef logic [7:0]  lane_id_t;
    typedef logic [3:0]  module_id_t;
    typedef logic [7:0]  virtual_channel_t;
    
    // Common Status Types
    typedef enum logic [1:0] {
        STATUS_SUCCESS   = 2'b00,
        STATUS_ERROR     = 2'b01,
        STATUS_TIMEOUT   = 2'b10,
        STATUS_RETRY     = 2'b11
    } status_t;
    
    // Common Valid/Ready Interface
    typedef struct packed {
        logic valid;
        logic ready;
        logic [255:0] data;
        logic [31:0]  metadata;
    } common_interface_t;
    
    // Temperature and Thermal Management
    typedef logic [15:0] temperature_t;  // Temperature in 0.1°C units
    parameter temperature_t TEMP_CRITICAL = 16'd1000;  // 100.0°C
    parameter temperature_t TEMP_WARNING  = 16'd850;   // 85.0°C
    parameter temperature_t TEMP_NORMAL   = 16'd650;   // 65.0°C
    
    // Power Management Common Types
    typedef logic [15:0] power_mw_t;     // Power in milliwatts
    typedef logic [15:0] voltage_mv_t;   // Voltage in millivolts
    typedef logic [31:0] frequency_hz_t; // Frequency in Hz
    
    // Clock Domain Crossing Types
    typedef struct packed {
        logic [31:0] data;
        logic        valid;
        logic        toggle;
    } cdc_data_t;
    
    // Reset Synchronizer Parameters
    parameter int RESET_SYNC_STAGES = 3;
    parameter int CDC_SYNC_STAGES = 2;
    
    // Common Utility Functions
    
    // Gray code encoder
    function automatic logic [31:0] binary_to_gray(logic [31:0] binary);
        return binary ^ (binary >> 1);
    endfunction
    
    // Gray code decoder
    function automatic logic [31:0] gray_to_binary(logic [31:0] gray);
        logic [31:0] binary = gray;
        for (int i = 1; i < 32; i++) begin
            binary = binary ^ (gray >> i);
        end
        return binary;
    endfunction
    
    // Population count (number of 1s)
    function automatic int popcount(logic [63:0] data);
        int count = 0;
        for (int i = 0; i < 64; i++) begin
            if (data[i]) count++;
        end
        return count;
    endfunction
    
    // Leading zero count
    function automatic int leading_zeros(logic [31:0] data);
        for (int i = 31; i >= 0; i--) begin
            if (data[i]) return (31 - i);
        end
        return 32;
    endfunction
    
    // Safe division with overflow protection
    function automatic logic [31:0] safe_divide(logic [31:0] dividend, logic [31:0] divisor);
        if (divisor == 0) return 32'hFFFFFFFF;  // Max value on divide by zero
        return dividend / divisor;
    endfunction
    
    // Calculate bandwidth in Gbps
    function automatic int calculate_bandwidth_gbps(int lanes, int rate_gt_per_s);
        return lanes * rate_gt_per_s;
    endfunction
    
    // Calculate power efficiency in pJ/bit
    function automatic int calculate_efficiency_pj_per_bit(int power_mw, int bandwidth_gbps);
        if (bandwidth_gbps == 0) return 32'hFFFFFFFF;
        return (power_mw * 1000) / bandwidth_gbps;  // Convert mW to pW, divide by Gbps
    endfunction
    
    // Temperature conversion utilities
    function automatic temperature_t celsius_to_temp(int celsius_x10);
        return temperature_t'(celsius_x10);
    endfunction
    
    function automatic int temp_to_celsius_x10(temperature_t temp);
        return int'(temp);
    endfunction
    
    // Power conversion utilities
    function automatic power_mw_t watts_to_mw(int watts);
        return power_mw_t'(watts * 1000);
    endfunction
    
    function automatic int mw_to_watts_x1000(power_mw_t mw);
        return int'(mw);
    endfunction
    
    // Clock frequency utilities
    function automatic frequency_hz_t mhz_to_hz(int mhz);
        return frequency_hz_t'(mhz * 1000000);
    endfunction
    
    function automatic int hz_to_mhz(frequency_hz_t hz);
        return int'(hz / 1000000);
    endfunction
    
    // Timing constraint helpers
    function automatic int ns_to_cycles(int nanoseconds, frequency_hz_t clock_freq);
        return int'((nanoseconds * clock_freq) / 1000000000);
    endfunction
    
    function automatic int cycles_to_ns(int cycles, frequency_hz_t clock_freq);
        return int'((cycles * 1000000000) / clock_freq);
    endfunction
    
    // Error detection and correction utilities
    function automatic logic [7:0] calculate_ecc_syndrome(logic [63:0] data, logic [7:0] ecc);
        // Simple Hamming code syndrome calculation
        logic [7:0] syndrome = 8'h0;
        // Simplified ECC - would need full implementation for production
        syndrome[0] = ^{data[0], data[1], data[3], data[4], data[6], data[8], data[10], data[11], data[13], data[15], ecc[0]};
        syndrome[1] = ^{data[0], data[2], data[3], data[5], data[6], data[9], data[10], data[12], data[13], data[16], ecc[1]};
        syndrome[2] = ^{data[1], data[2], data[3], data[7], data[8], data[9], data[10], data[14], data[15], data[16], ecc[2]};
        syndrome[3] = ^{data[4], data[5], data[6], data[7], data[8], data[9], data[10], ecc[3]};
        syndrome[4] = ^{data[11], data[12], data[13], data[14], data[15], data[16], ecc[4]};
        syndrome[5] = ecc[5];  // Additional parity bits
        syndrome[6] = ecc[6];
        syndrome[7] = ecc[7];
        return syndrome;
    endfunction
    
    // Constants for system configuration
    parameter int MAX_SYSTEM_LANES = 256;        // Maximum lanes in system
    parameter int MAX_SYSTEM_MODULES = 16;       // Maximum modules in system
    parameter int MAX_VIRTUAL_CHANNELS = 32;     // Maximum VCs per protocol
    parameter int MAX_PROTOCOLS_PER_MODULE = 8;  // Maximum protocols per module
    
    // System performance targets
    parameter int TARGET_BANDWIDTH_TBPS = 8;     // 8.192 Tbps target
    parameter int TARGET_POWER_BUDGET_W = 6;     // 6W total power budget
    parameter int TARGET_LATENCY_NS = 50;        // 50ns target latency
    parameter int TARGET_EFFICIENCY_PJ_BIT = 1;  // <1 pJ/bit target efficiency
    
    // Common assertion helpers
    `define COMMON_ASSERT_CLK(clk, rst, cond, msg) \
        assert property (@(posedge clk) disable iff (!rst) (cond)) \
        else $error("[COMMON_PKG] ASSERTION FAILED: %s", msg);
    
    `define COMMON_ASSERT_RANGE(val, min_val, max_val, msg) \
        assert ((val >= min_val) && (val <= max_val)) \
        else $error("[COMMON_PKG] RANGE CHECK FAILED: %s (val=%0d, range=[%0d:%0d])", msg, val, min_val, max_val);
    
    // Common coverage macros
    `define COMMON_COVER_VAL(val, bins, msg) \
        covergroup cg_``val; \
            val``_cp: coverpoint val { bins val``_bins[] = bins; } \
            option.comment = msg; \
        endgroup

endpackage