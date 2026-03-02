SIM    = iverilog
SIMRUN = vvp
TB     = tb.v
DUT    = ../src/project.v
OUT    = sim.vvp

all: $(OUT)
	$(SIMRUN) $(OUT)

$(OUT): $(TB) $(DUT)
	$(SIM) -g2012 -o $(OUT) $(TB) $(DUT)

clean:
	rm -f $(OUT) *.vcd

.PHONY: all clean
