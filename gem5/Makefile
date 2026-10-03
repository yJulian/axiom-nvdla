ROOT := ..
MODE ?= loose
LATENCY ?= 10ns
WORKLOAD ?= relu
GEM5 ?= /home/julian/Development/axiom/build/RISCV/gem5.opt

.PHONY: run
run:
	python3 $(ROOT)/gem5/collect.py --gem5 $(GEM5) --mode $(MODE) --latency $(LATENCY) --workload $(WORKLOAD)
