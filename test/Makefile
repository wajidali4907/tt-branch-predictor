cd ~/tt-branch-predictor/test

# Overwrite the Makefile completely
cat > Makefile << 'EOF'
SIM    = iverilog
SIMRUN = vvp
TB     = tb.v
DUT    = ../src/project.v
OUT    = sim.vvp

all: $(OUT)
	$(SIMRUN) $(OUT) | tee sim.log
	@if grep -q "Simulation Succeeded" sim.log; then \
		echo '<?xml version="1.0" encoding="UTF-8"?>' > results.xml; \
		echo '<testsuites><testsuite name="tt_branch_predictor" tests="1" errors="0" failures="0">' >> results.xml; \
		echo '<testcase name="simulation" classname="tb"/>' >> results.xml; \
		echo '</testsuite></testsuites>' >> results.xml; \
	else \
		echo '<?xml version="1.0" encoding="UTF-8"?>' > results.xml; \
		echo '<testsuites><testsuite name="tt_branch_predictor" tests="1" errors="1" failures="1">' >> results.xml; \
		echo '<testcase name="simulation" classname="tb"><failure message="Simulation Failed"/></testcase>' >> results.xml; \
		echo '</testsuite></testsuites>' >> results.xml; \
		exit 1; \
	fi

$(OUT): $(TB) $(DUT)
	$(SIM) -g2012 -o $(OUT) $(TB) $(DUT)

clean:
	rm -f $(OUT) *.vcd sim.log results.xml

.PHONY: all clean
EOF