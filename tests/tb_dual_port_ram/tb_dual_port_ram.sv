`timescale 1ns/1ps

module tb_dual_port_ram #(  
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter SEL_WIDTH  = DATA_WIDTH/8
);

    // Port indices
    localparam PA = 0;
    localparam PB = 1;

    // Clock & reset
    logic clk = 0;
    logic rst;
    always #5 clk = ~clk; // 100 MHz

    // Wishbone signals for both ports [0]=A, [1]=B
    logic [ADDR_WIDTH-1:0]    wb_addr_i  [1:0];
    logic [DATA_WIDTH-1:0]    wb_data_i  [1:0];
    logic [SEL_WIDTH-1:0]     wb_sel_i   [1:0];
    logic                     wb_we_i    [1:0];
    logic                     wb_stb_i   [1:0];
    logic                     wb_ack_o   [1:0];
    logic                     wb_stall_o [1:0];
    logic [DATA_WIDTH-1:0]    wb_data_o  [1:0];

    // DUT instantiation
    dual_port_ram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .wb_addr_i  (wb_addr_i),
        .wb_data_i  (wb_data_i),
        .wb_sel_i   (wb_sel_i),
        .wb_we_i    (wb_we_i),
        .wb_stb_i   (wb_stb_i),
        .wb_ack_o   (wb_ack_o),
        .wb_stall_o (wb_stall_o),
        .wb_data_o  (wb_data_o)
    );

    // Generic write task
    task automatic write_port(
        input int port,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        begin
            @(posedge clk);
            wb_addr_i[port] = addr;
            wb_data_i[port] = data;
            wb_sel_i[port]  = {SEL_WIDTH{1'b1}};
            wb_we_i[port]   = 1;
            wb_stb_i[port]  = 1;
            wait (wb_ack_o[port] && !wb_stall_o[port]);
            wb_stb_i[port]  = 0;
            wb_we_i[port]   = 0;
            $display("WRITE Port %0s: addr=0x%0h, data=0x%0h", (port != 0) ? "B" : "A", addr, data);
        end
    endtask

    // Generic read task
    task automatic read_port(
        input int port,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] expected
    );
        begin
            @(posedge clk);
            wb_addr_i[port] = addr;
            wb_sel_i[port]  = {SEL_WIDTH{1'b1}};
            wb_we_i[port]   = 0;
            wb_stb_i[port]  = 1;
            wait (wb_ack_o[port] && !wb_stall_o[port]);
            wb_stb_i[port]  = 0;
            if (wb_data_o[port] !== expected)
                $error("FAIL Port %0s: got 0x%0h, expected 0x%0h", (port != 0) ? "B" : "A", wb_data_o[port], expected);
            else
                $display("PASS Port %0s: read 0x%0h", (port != 0) ? "B" : "A", wb_data_o[port]);
        end
    endtask

    initial begin
        $dumpfile("tb_dual_port_ram.vcd");
        $dumpvars(1, tb_dual_port_ram);

        // Reset
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        // Test 1: non-conflicting writes
        write_port(PA, 9'h00,    32'hDEADBEEF);
        write_port(PB, 9'h100,   32'hFACEFACE);

        // Test 2: non-conflicting reads
        read_port(PA, 9'h00,    32'hDEADBEEF);
        read_port(PB, 9'h100,   32'hFACEFACE);

        // Test 3: conflict on mem0 (both A/B access same macro)
        // A has priority, B must wait
        @(posedge clk);
        wb_addr_i[PA] = 9'h010;
        wb_addr_i[PB] = 9'h011;
        wb_data_i[PA] = 32'hAAAA1234;
        wb_data_i[PB] = 32'hBBBB5678;
        wb_sel_i[PA]  = {SEL_WIDTH{1'b1}};
        wb_sel_i[PB]  = {SEL_WIDTH{1'b1}};
        wb_we_i[PA]   = 1;
        wb_we_i[PB]   = 1;
        wb_stb_i[PA]  = 1;
        wb_stb_i[PB]  = 1;

        // wait A then B
        wait (wb_ack_o[PA]);
        wb_stb_i[PA] = 0;
        wb_we_i[PA]  = 0;
        wait (wb_ack_o[PB]);
        wb_stb_i[PB] = 0;
        wb_we_i[PB]  = 0;

        $display("All tests completed.");
        $finish;
    end

endmodule
