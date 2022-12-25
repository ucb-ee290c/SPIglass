/*
Implements a (CPOL, CPHA) = (0, 0) buffered SPI device.

This should model the SiFive FE310 SPI controller because:
* CPOL = 0 (reason: clock idles 0)
* CPHA = 0 (reason: MOSI updates on neg-edge, and since CPOL=0 this means we must be CPHA=0 per https://hackaday.com/wp-content/uploads/2016/06/spi_polarities1.png)
*/

module spi #(
    parameter OUT_BUFFER_BITS = 8,
    parameter IN_BUFFER_BITS  = 8
) (
    /* SPI signals */
    input clk,
    input cs,
    input mosi,
    output reg miso,

    /* Interface */
    input reset,
    /* 
    Syncrounous and valid only as long as MOSI is valid. That is, until the
    negative edge of the SPI clock. This is awkward but it allows for the fast
    access to the current cycle's bit
    */
    output reg [OUT_BUFFER_BITS - 1 : 0] out_buffer,
    /* Strobes on every OUT_BUFFER_BITS captured */ 
    output reg out_strobe,

    input [IN_BUFFER_BITS - 1 : 0] in_buffer,
    output in_buffer_ready,
    input in_buffer_valid
);
    /* CS is active low */
    wire chip_en = !cs;

    /* ~* MOSI *~ */

    /* Drive the counter and strobe */
    // This field can be thought of as the _out_buffer buffered bit count
    reg [$clog2(OUT_BUFFER_BITS) - 1 : 0] out_buffer_cnt;

    /* Strobe when we're going to overflow this cycle */
    /* verilator lint_off WIDTH */
    wire _out_strobe = chip_en && (out_buffer_cnt == OUT_BUFFER_BITS - 1);
    /* lint_on */

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            out_buffer_cnt <= 0;
        end
        else if (chip_en) begin
            if (_out_strobe) begin
                out_buffer_cnt <= 0;
            end
            else begin
                out_buffer_cnt <= out_buffer_cnt + 1;
            end
        end
        else begin
            /* 
            XXX: unclear what the expected behavior is when a chip is 
            deselected mid transaction. Hold, I guess?
            */
            out_buffer_cnt <= out_buffer_cnt;
        end
    end

    always @(posedge clk, negedge chip_en) begin
        if (!chip_en) begin
            out_strobe <= _out_strobe;
        end
        else begin
            out_strobe <= _out_strobe;
        end
    end

    /* Drive out_buffer */
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            out_buffer <= 0;
        end
        else if (chip_en) begin
            /* We're capturing! Shift in */
            out_buffer <= (out_buffer << 1) | mosi;
        end
        else begin
            out_buffer <= out_buffer;
        end
    end

    /* ~* MISO *~ */

    /*
    MISO expects users to set in_buffer only on the negative edge of the clock
    and then hold it till the positive edge.
    This is done to provide zero cycle transmit delay.
    */
    /* Drive in_buffer_ready */
    reg [$clog2(IN_BUFFER_BITS) - 1 : 0] in_buffer_cnt;
    assign in_buffer_ready = (in_buffer_cnt == 0);
    wire will_internalize = in_buffer_ready && in_buffer_valid;
    always @(negedge clk, posedge reset) begin
        if (reset) begin
            in_buffer_cnt <= 0;
        end
        else if (chip_en) begin
            if (!in_buffer_ready) begin
                in_buffer_cnt <= in_buffer_cnt + 1;
            end
            else if (will_internalize) begin
                /* 
                We're going to internalize. This means we're also TXing this
                round, so start at 1.
                */
                in_buffer_cnt <= 1;
            end
            else begin
                /* We're ready but there's nothing to internalize. Hold. */
                in_buffer_cnt <= in_buffer_cnt;
            end
            
        end
        else begin
            /* XXX: hold if we're not selected... */
            in_buffer_cnt <= in_buffer_cnt;
        end
    end

    /* Drive _in_buffer */
    reg [IN_BUFFER_BITS - 2 : 0] _in_buffer;
    always @(negedge clk, posedge reset) begin
        if (reset) begin
            _in_buffer <= 0;
        end
        else if (will_internalize) begin
            /* 
            We only internalize the upper bits because transmit [0] this cycle
            */
            _in_buffer <= in_buffer[IN_BUFFER_BITS - 2 : 0];
        end
        else if (chip_en) begin
            /* We're transmitting this cycle, shift out */
            _in_buffer <= _in_buffer << 1;
        end
        else begin
            /* We're not transmitting this cycle, hold... */
            _in_buffer <= _in_buffer;
        end
    end

    /* Drive MISO */
    always @(*) begin
        if (!chip_en) begin
            miso = 1'bx; 
        end
        else if (will_internalize) begin
            miso = in_buffer[IN_BUFFER_BITS - 1];
        end
        else begin
            miso = _in_buffer[IN_BUFFER_BITS - 2];
        end
    end
endmodule