NVIM ?= nvim

.PHONY: test format lint check

test:
	$(NVIM) --headless -u NONE -l tests/run.lua

format:
	stylua lua plugin tests

lint:
	selene lua plugin

check: test lint
