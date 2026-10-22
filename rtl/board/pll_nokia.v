// 27 MHz -> 16.875 MHz Nokia ARM / SDRAM clock.
// plus the same clock shifted by 180 degrees for the SDRAM chip.
module pll_nokia(
        input  clock_in,
        output clk_sys,
        output clk_sys_p,
        output locked
    );

    rPLL #(
        .FCLKIN("27.0"),
        .IDIV_SEL(7),        // PFD = 3.375 MHz
        .FBDIV_SEL(4),       // CLKOUT = 16.875 MHz
        .ODIV_SEL(32),       // VCO = 540 MHz
        .PSDA_SEL("1000"),   // CLKOUTP = 180 deg
        .DUTYDA_SEL("1000"),
        .DEVICE("GW2A-18C")
    ) pll (.CLKOUTD(), .CLKOUTD3(), .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0), .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
        .CLKIN(clock_in),
        .CLKOUT(clk_sys),
        .CLKOUTP(clk_sys_p),
        .LOCK(locked)
    );

endmodule
