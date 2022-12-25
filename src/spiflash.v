`include "spi_instructions.vh"

module spiflash #(
    parameter ADDRL = 14
) (
    input reset,
    /* The SPI clock, external and non-periodic */
    input clk,
    input cs,
    input mosi,
    output miso
);
    wire chip_en = !cs;

    wire [7 : 0] spi_out;
    wire spi_out_strobe;
    reg [7 : 0] spi_in;
    reg spi_in_valid;
    wire spi_in_ready;

    spi #(
        .OUT_BUFFER_BITS(8),
        .IN_BUFFER_BITS(8)
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

    wire [ADDRL - 1 : 0] storage_addra;
    wire [ADDRL - 1 : 0] storage_addrb;
    wire [7 : 0] storage_dia, storage_dob;
    wire storage_wea;
    reg flash_write_enabled;

    simple_dual_one_clock_neg #(
        .ADDRL(ADDRL)
    ) storage (
        .clk(clk),
        .ena(1'b1),
        .enb(1'b1),
        .wea(storage_wea),
        .addra(storage_addra),
        .addrb(storage_addrb),
        .dia(storage_dia),
        .dob(storage_dob)
    );

    /*
    Simple state machine for the flash controller.
    */
    localparam STATE_INSTRUCTION_READ   = 2'b00;
    localparam STATE_ARGUMENT_READ      = 2'b01;
    /* 
    Entered when an instruction is executing. This state may be exited
    automatically by the end of the operation or by chip_en going low.
    */
    localparam STATE_EXECUTE            = 2'b10;
    /* Error state, caused by an unrecognized instruction */
    localparam STATE_FAULT              = 2'b11;
    reg [1 : 0] state;
    reg [1 : 0] state_next;
    
    localparam MAX_ARGUMENT_COUNT       = 5;
    reg [$clog2(MAX_ARGUMENT_COUNT) - 1 : 0] arguments_remaining;
    localparam ARGUMENTS_BIT_LEN        = (8 * MAX_ARGUMENT_COUNT) - 1;
    /* 
    Provides a bypass/"earlier" view into arguments which allows access to the
    final argument before it is latched into _arguments
    */
    reg [ARGUMENTS_BIT_LEN - 1 : 0] arguments;
    reg [ARGUMENTS_BIT_LEN - 1 : 0] _arguments;

    reg [7 : 0] _instruction;
    reg [7 : 0] instruction;

    reg incoming_instruction_valid;
    reg [$clog2(MAX_ARGUMENT_COUNT + 1) - 1: 0] incoming_instruction_arg_count;

    /* Manage instruction latching */
    always @(posedge clk) begin
        if (spi_out_strobe && state == STATE_INSTRUCTION_READ) begin
            _instruction <= spi_out;
        end
        else begin
            _instruction <= instruction;
        end
    end
    /* Early instruction access */
    always @(*) begin
        if (state == STATE_INSTRUCTION_READ) begin
            instruction = spi_out;
        end
        else begin
            instruction = _instruction;
        end
    end

    /* Manage instruction decode */
    always @(*) begin
        case (instruction)
            `SF_WRITE_ENABLE, `SF_WRITE_DISABLE: begin
                incoming_instruction_valid = 1'b1;
                incoming_instruction_arg_count = 0;
            end
            `SF_READ_DATA, `SF_PAGE_PROGRAM: begin
                incoming_instruction_valid = 1'b1;
                incoming_instruction_arg_count = 3;
            end
            default: begin
                incoming_instruction_valid = 1'b0;
                /* verilator lint_off WIDTH */
                incoming_instruction_arg_count = 'bx;
                /* lint_on */
            end
        endcase
    end

    /* Manage state machine */
    always @(*) begin
        if (reset) begin
            state_next = STATE_INSTRUCTION_READ;
        end
        else
        case (state)
            STATE_INSTRUCTION_READ: begin
                if (chip_en && spi_out_strobe) begin
                    if (incoming_instruction_valid) begin
                        if (incoming_instruction_arg_count != 0) begin
                            state_next = STATE_ARGUMENT_READ;
                        end
                        else begin
                            /* No arguments, execute directly */
                            state_next = STATE_EXECUTE;
                        end
                    end
                    else begin
                        /* Instruction is not valid, fault */
                        state_next = STATE_FAULT;
                    end
                end
                else begin
                    /* Not strobing but we need an instruction to continue. */
                    state_next = STATE_INSTRUCTION_READ;
                end
            end

            STATE_ARGUMENT_READ: begin
                if (chip_en && spi_out_strobe) begin
                    if (arguments_remaining == 1) begin
                        /* 
                        Our final argument is available. We do actually need to
                        execute in *this* cycle in time for negedge but we move
                        to execute now regardless.
                        */
                        state_next = STATE_EXECUTE;
                    end
                    else begin
                        /* We have more arguments to read... */
                        state_next = STATE_ARGUMENT_READ;
                    end
                end
                else begin
                    /* No strobe, so no arguments were read. Spin. */
                    state_next = STATE_ARGUMENT_READ;
                end
            end

            STATE_EXECUTE: begin
                if (!chip_en) begin
                    /* CHIP_EN deasserted, end the instruction */
                    state_next = STATE_INSTRUCTION_READ;
                end
                else begin
                    /* We're still good to go... */
                    state_next = STATE_EXECUTE;
                end
            end

            default: begin
                /* Unknown or intentionally invalid state. Halt. */
                state_next = STATE_FAULT;
            end 
        endcase
    end

    /* 
    Manage state update 
    We're sensative to neg CHIP_EN to transition back when we are deslected
    */
    always @(posedge clk, negedge chip_en) begin
        /* need to repeat to solve ambiguous clock issue */
        if (!chip_en) begin
            state <= state_next;
        end
        else begin
            state <= state_next;
        end
    end

    /* Manage argument bypass */
    always @(*) begin
        /* We're currently reading our argument, so provide early access to it*/
        if (state != STATE_EXECUTE && state_next == STATE_EXECUTE) begin
            arguments = {_arguments[ARGUMENTS_BIT_LEN - 1 - 8 : 0], spi_out};
        end
        else begin
            /* Latched arguments is valid */
            arguments = _arguments;
        end
    end

    /* Manage argument latching */
    always @(posedge clk) begin
        if (state == STATE_ARGUMENT_READ && spi_out_strobe) begin
            _arguments <= {_arguments[ARGUMENTS_BIT_LEN - 1 - 8 : 0], spi_out};
        end
        else begin
            _arguments <= _arguments;
        end
    end

    /* Manage argument count */
    always @(posedge clk) begin
        if (state == STATE_INSTRUCTION_READ) begin
            arguments_remaining <= incoming_instruction_arg_count;
        end
        else if (state == STATE_ARGUMENT_READ && spi_out_strobe) begin
            arguments_remaining <= arguments_remaining - 1;
        end
        else begin
            arguments_remaining <= arguments_remaining;
        end
    end

    /* Execute instructions */
    wire is_executing = (state == STATE_EXECUTE || state_next == STATE_EXECUTE);
    //XXX: Kinda jank, but we can use the SPI out strobe to detect when we need
    //     to start generating a response bank (as the strobe is launched on the
    //     8th beat after the completion of the first message.
    wire prepare_to_execute_strobe = spi_out_strobe && is_executing;

    /* Manage address generation for streaming read/write instructions */
    wire [ADDRL - 1 : 0] address_args = arguments[ADDRL - 1 : 0];
    reg [ADDRL - 1 : 0] address_i;
    reg [ADDRL - 1 : 0] address;
    always @(negedge clk) begin
        if (prepare_to_execute_strobe) begin
            if (instruction == `SF_READ_DATA && state != STATE_EXECUTE) begin
                /* 
                This is our first entrance, generate the next address based on
                the arguments
                */
                address_i <= address_args + 1;
            end
            else if (instruction == `SF_PAGE_PROGRAM && state != STATE_EXECUTE)
            begin
                /*
                Program instructions, unlike reads, do not increment on the
                first strobe. This is because we have to wait for the first data
                byte (which arrives on the first strobe). Thus, skip the first
                increment since we'll be using this address one cycle later.
                */
                address_i <= address_args;
            end
            else begin
                /*
                SPI read/write allows continuous reading/writing until the
                instruction is terminated by deselecting the chip. After each
                byte read, we simply increment.
                */
                address_i <= address_i + 1;
            end
        end
        else begin
            address_i <= address_i;
        end
    end

    always @(*) begin
        if (state != STATE_EXECUTE) begin
            /* 
            We're the first operation, use the address derived from the argument
            rather than the incrementing address
            */
            address = address_args;
        end
        else begin
            address = address_i;
        end
    end
    // We can read directly from the streaming address as incrementing is fine
    assign storage_addrb = address;

    /*
    Combinatorially mux SPI_IN and manage SPI_IN_VALID
    */
    reg _spi_in_valid;
    always @(*) begin
        if (is_executing) begin
            case (instruction)
                `SF_READ_DATA: begin
                    _spi_in_valid = 1'b1;
                    spi_in = storage_dob;
                end
                default: begin
                    /* Non-transmitting instruction */
                    _spi_in_valid = 1'b0;
                    spi_in = 8'bx;
                end
            endcase
        end
        else begin
            /* We're not executing, so don't care. */
            spi_in = 8'bx;
            _spi_in_valid = 1'b0;
        end
    end

    always @(negedge clk) begin
            spi_in_valid <= _spi_in_valid & prepare_to_execute_strobe;
    end

    /* Manage flash_write_enabled */
    always @(negedge clk, posedge reset) begin
        if (reset) begin
            flash_write_enabled <= 0;
        end
        else if (prepare_to_execute_strobe && instruction == `SF_WRITE_ENABLE) 
        begin
            flash_write_enabled <= 1;
        end
        else if (prepare_to_execute_strobe && instruction == `SF_WRITE_DISABLE) 
        begin
            flash_write_enabled <= 0;
        end
        else begin
            flash_write_enabled <= flash_write_enabled;
        end
    end

    /* Manage write commands (PAGE_PROGRAM) */
    /* 
    Hack up the read streaming address to make it work for page wrapping.
    We do this by taking the static page address and then using the incrementing
    offset for the page offset
    */
    assign storage_addra = {address_args[ADDRL - 1 : 8], address[7 : 0]};
    assign storage_dia = spi_out;
    /* 
    Require the current state be execute so that the strobe refers to the
    incoming data byte rather than the incoming final address byte
    */
    assign storage_wea = spi_out_strobe && state == STATE_EXECUTE 
                    && instruction == `SF_PAGE_PROGRAM && flash_write_enabled;
    
endmodule