`timescale 1ns/1ns
`define CLK_PERIOD 8
`define CYCLES_PER_SECOND_SIMULATED 10

module spi_tb();
    localparam OUT_BITS = 8;
    localparam IN_BITS = 8;
    /* Generate the simulated clock */
    reg clk = 0;
    reg clk_en = 0;
    always begin
        if (clk_en) begin
            #(`CLK_PERIOD/2);
            clk = ~clk;
        end
        else begin
            #(`CLK_PERIOD/2);
            clk = 0;
        end
    end
    /* Managed signals */
    reg mosi, cs, reset;
    wire miso, spi_in_ready, spi_out_strobe;
    wire [OUT_BITS - 1 : 0] spi_out;
    reg [IN_BITS - 1 : 0] spi_in;
    reg spi_in_valid;

    spi #(
        .OUT_BUFFER_BITS(OUT_BITS),
        .IN_BUFFER_BITS(IN_BITS)
    ) spi (
        .clk(clk),
        .cs(cs),
        .mosi(mosi),
        .miso(miso),
        .reset(reset),
        .out_buffer(spi_out),
        .out_strobe(spi_out_strobe),
        .in_buffer(spi_in),
        .in_buffer_ready(spi_in_ready),
        .in_buffer_valid(spi_in_valid)
    );

    task do_spi_mosi(
        input [OUT_BITS - 1 : 0] data
    );
        integer i;
        clk_en = 1;
        cs = 0;

        for (i = OUT_BITS - 1; i > 0; i -= 1) begin
            // assert(!spi_out_strobe) else 
            //     $error("spi_out_strobe high during early rx [i =%d]", i);
            mosi = data[i];
            
            @(negedge clk);
        end
        mosi = data[0];
        @(posedge clk); #1;
        assert(spi_out_strobe) else 
            $error("spi_out_strobe not set for async rx");
        assert(spi_out == data) else
            $error("spi_out incorrect. Got %d, expected %d", spi_out, data);
        @(negedge clk);
        clk_en = 0;
        cs = 1;
        #128;
    endtask

    task do_spi_miso(
        input [OUT_BITS - 1 : 0] data
    );
        integer i;
        clk_en = 1;
        cs = 0;
        @(negedge clk)

        assert(spi_in_ready) else 
            $error("spi in not ready? %d", spi_in_ready);
        
        spi_in = data;
        spi_in_valid = 1;
        for (i = OUT_BITS - 1; i >= 0; i -= 1) begin
            @(posedge clk);
            
            assert(miso == data[i]) else
                $error("bad miso value: expected %d got %d", data[i], miso);
            @(negedge clk);
            spi_in_valid = 0;
        end
        /* Disable the chip so we can clock screw */
        cs = 1;
        /* Try simulating talking to someone else */
        repeat (5) @(negedge clk);
        /* Turn the clock off and advance a bit */
        clk_en = 0;
        #21;
    endtask

    initial begin
    `ifdef IVERILOG
        $dumpfile("spi_tb.fst");
        $dumpvars(0, spi_tb);
        $dumpvars(0, spi);
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

    assert(spi._in_buffer == 0) else
        $error("Reset failed, got %d", spi._in_buffer);
    
    clk_en = 1;
    cs = 0;
    do_spi_mosi(8'b1111_1111);
    do_spi_mosi(8'b0000_0001);
    do_spi_mosi(8'b0101_0101);
    do_spi_mosi(8'b1000_0000);
    do_spi_mosi(8'b1011_0011);
    do_spi_miso(8'b1111_1111);
    do_spi_miso(8'b0000_0001);
    do_spi_miso(8'b0101_0101);
    do_spi_miso(8'b1000_0000);
    do_spi_miso(8'b1011_0011);


    $display("Done!");
    `ifndef IVERILOG
        $vcdplusoff;
    `endif
    $finish();

    end
endmodule