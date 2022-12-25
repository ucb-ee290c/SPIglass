`timescale 1ns/1ns
`define CLK_PERIOD 8
`define CYCLES_PER_SECOND_SIMULATED 10
`include "spi_instructions.vh"

module spiflash_tb();
    localparam OUT_BITS = 8;
    localparam IN_BITS = 8;
    /* Generate the simulated clock */
    reg clk = 0;
    reg clk_en = 0;
    always begin
        if (clk_en) begin
            clk = ~clk;
            #(`CLK_PERIOD/2);
        end
        else begin
            clk = 0;
            #(`CLK_PERIOD/2);
        end
    end
    /* Managed signals */
    reg mosi, cs, reset;
    wire miso, master_in_ready, master_out_strobe;
    wire [OUT_BITS - 1 : 0] master_out;
    reg [IN_BITS - 1 : 0] master_in;
    reg master_in_valid;

    spi #(
        .OUT_BUFFER_BITS(OUT_BITS),
        .IN_BUFFER_BITS(IN_BITS)
    ) spi_tb (
        .clk(clk),
        .cs(cs),
        .mosi(miso),
        .miso(mosi),
        .reset(reset),
        .out_buffer(master_out),
        .out_strobe(master_out_strobe),
        .in_buffer(master_in),
        .in_buffer_ready(master_in_ready),
        .in_buffer_valid(master_in_valid)
    );

    spiflash #(
        .ADDRL(22)
    ) spiflash (
        .clk(clk),
        .cs(cs),
        .mosi(mosi),
        .miso(miso),
        .reset(reset)
    );

    task do_tx(
        input [OUT_BITS - 1 : 0] data
    );
        master_in = data;
        master_in_valid = 1;
        repeat (8) @(negedge clk);
    endtask

    task do_rx_assert(
        input [OUT_BITS - 1 : 0] data
    );
        repeat (8) @(negedge clk);
        assert(master_out_strobe) else 
            $error("spi_out_strobe not set for rx");
        assert(data == master_out) else
            $error("SPI out: got 0x%x, expected 0x%x", master_out, data);
    endtask

    task start_command();
        cs = 0;
        #11;
        clk_en = 1;    
    endtask

    task end_command();
        clk_en = 0;
        #7;
        cs = 1;
        #8;
    endtask

    task set_write_enabled(
        input en
    );
        start_command();
        do_tx(en ? `SF_WRITE_ENABLE : `SF_WRITE_DISABLE);
        end_command();

        assert(spiflash.flash_write_enabled == en) else 
            $error("Write enable/disable failed: got %d, expected %d", 
                spiflash.flash_write_enabled, en);
    endtask
    integer i;
    reg [23 : 0] base_addr;
    initial begin
    `ifdef IVERILOG
        $dumpfile("spiflash_tb.fst");
        $dumpvars(0, spiflash_tb);
        $dumpvars(0, spi_tb);
        $dumpvars(0, spiflash);
    `endif
    `ifndef IVERILOG
        $vcdpluson;
        $vcdplusmemon;
    `endif

    /* Simulate async reset */
    cs = 1;
    reset = 1;
    #1;
    reset = 0;
    #1;
    

    /* Test flash write enable */
    set_write_enabled(1);    
    /* Test a string read */
    base_addr = 24'h0000AA;
    for (i = 0; i < 16; i += 1) begin
        spiflash.storage.ram[base_addr + i] = 'h41 + i;
    end
    
    start_command();
    do_tx(`SF_READ_DATA);
    do_tx(base_addr[23 : 16]);
    do_tx(base_addr[15 : 8]);
    do_tx(base_addr[7 : 0]);

    for (i = 0; i < 16; i += 1) begin
        do_rx_assert(spiflash.storage.ram[base_addr + i]);
    end
    end_command();

    /* Test write disable */
    // Ensure writes are still enabled
    assert(spiflash.flash_write_enabled == 1) else 
        $error("Write disable failed: %x", spiflash.flash_write_enabled);
    set_write_enabled(0);

    /* Test a string read, again for good measure */
    base_addr = 24'h0101AA;
    for (i = 0; i < 16; i += 1) begin
        spiflash.storage.ram[base_addr + i] = 'hB0 + i;
    end
    start_command();
    do_tx(`SF_READ_DATA);
    do_tx(base_addr[23 : 16]);
    do_tx(base_addr[15 : 8]);
    do_tx(base_addr[7 : 0]);
    for (i = 0; i < 16; i += 1) begin
        do_rx_assert(spiflash.storage.ram[base_addr + i]);
    end
    end_command();
    

    /* Test page program */
    // Enable writing
    set_write_enabled(1);
    base_addr = 24'h0101AA + 4;
    start_command();
    do_tx(`SF_PAGE_PROGRAM);
    do_tx(base_addr[23 : 16]);
    do_tx(base_addr[15 : 8]);
    do_tx(base_addr[7 : 0]);
    for (i = 0; i < 8; i += 1) begin
        do_tx(8'hC0 + i);
    end
    end_command();
    // for (i = 0; i < 16; i += 1) begin
    //     $display("%x] %x", base_addr - 4 + i, spiflash.storage.ram[base_addr + i - 4]);
    // end
    for (i = 0; i < 4; i += 1) begin
        assert(spiflash.storage.ram[base_addr + i - 4] == 'hB0 + i) else
            $error("Write left bleed: got 0x%x, expected 0x%x", 
                spiflash.storage.ram[base_addr + i - 4], 'hB0 + i);
    end

    for (i = 0; i < 8; i += 1) begin
        assert(spiflash.storage.ram[base_addr + i] == 'hC0 + i) else
            $error("Write failure: got 0x%x, expected 0x%x", 
                spiflash.storage.ram[base_addr + i], 'hC0 + i);
    end

    for (i = 12; i < 16; i += 1) begin
        assert(spiflash.storage.ram[base_addr + i - 4] == 'hB0 + i) else
            $error("Write right bleed: got 0x%x, expected 0x%x", 
                spiflash.storage.ram[base_addr + i - 4], 'hB0 + i);
    end

    $display("Done!");
    `ifndef IVERILOG
        $vcdplusoff;
    `endif
    $finish();

    end
endmodule