SHELL := /usr/bin/env bash

.PHONY: bootstrap doctor verify quick model kontrol target-test clean

bootstrap:
	./scripts/bootstrap

doctor:
	./scripts/doctor

verify:
	./scripts/verify full

quick:
	./scripts/verify quick

model:
	./scripts/verify model

kontrol:
	./scripts/verify kontrol

target-test:
	./scripts/verify target-test

clean:
	rm -rf results/* verification/solidity/cache verification/solidity/out verification/solidity/.kontrol
	touch results/.gitkeep
