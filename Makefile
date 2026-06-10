VERSION := $(shell echo $(shell git describe --tags) | sed 's/^v//')
COMMIT := $(shell git log -1 --format='%H')
BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
DOCKER_BUF := docker run -v $(shell pwd):/workspace --workdir /workspace bufbuild/buf
DOCKER := $(shell which docker)
HTTPS_GIT := https://github.com/cosmos/iavl.git
GO := GOTOOLCHAIN=go1.24.11 go

PDFFLAGS := -pdf --nodefraction=0.1
CMDFLAGS := -ldflags -X TENDERMINT_IAVL_COLORS_ON=on 
LDFLAGS := -ldflags "-X github.com/cosmos/iavl.Version=$(VERSION) -X github.com/cosmos/iavl.Commit=$(COMMIT) -X github.com/cosmos/iavl.Branch=$(BRANCH)"

all: lint test install

install:
ifeq ($(COLORS_ON),)
	$(GO) install ./cmd/iaviewer
else
	$(GO) install $(CMDFLAGS) ./cmd/iaviewer
endif
.PHONY: install

build:
	@echo "--> Building iaviewer"
	@$(GO) build $(LDFLAGS) ./cmd/iaviewer
.PHONY: build

test-short:
	@echo "--> Running go test"
	@$(GO) test ./... $(LDFLAGS) -v --race --short
.PHONY: test-short

test:
	@echo "--> Running go test"
	@$(GO) test ./... $(LDFLAGS) -v 
.PHONY: test

format:
	find . -name '*.go' -type f -not -path "*.git*" -not -name '*.pb.go' -not -name '*pb_test.go' | xargs gofmt -w -s
	find . -name '*.go' -type f -not -path "*.git*"  -not -name '*.pb.go' -not -name '*pb_test.go' | xargs goimports -format
.PHONY: format

# look into .golangci.yml for enabling / disabling linters
golangci_lint_cmd=$(shell $(GO) env GOPATH)/bin/golangci-lint
golangci_version=v1.64.8

lint:
	@echo "--> Running linter"
	@$(GO) install github.com/golangci/golangci-lint/cmd/golangci-lint@$(golangci_version)
	@$(golangci_lint_cmd) run --timeout=10m --concurrency 2

lint-fix:
	@echo "--> Running linter"
	@$(GO) install github.com/golangci/golangci-lint/cmd/golangci-lint@$(golangci_version)
	@$(golangci_lint_cmd) run --fix --out-format=tab --issues-exit-code=0 --concurrency 2

# bench is the basic tests that shouldn't crash an aws instance
bench:
	cd benchmarks && \
		$(GO) test $(LDFLAGS) -tags pebbledb -run=NOTEST -bench=Small . && \
		$(GO) test $(LDFLAGS) -tags pebbledb -run=NOTEST -bench=Medium . && \
		$(GO) test $(LDFLAGS) -run=NOTEST -bench=RandomBytes .
.PHONY: bench

# fullbench is extra tests needing lots of memory and to run locally
fullbench:
	cd benchmarks && \
		$(GO) test $(LDFLAGS) -run=NOTEST -bench=RandomBytes . && \
		$(GO) test $(LDFLAGS) -tags rocksdb,pebbledb -run=NOTEST -bench=Small . && \
		$(GO) test $(LDFLAGS) -tags rocksdb,pebbledb -run=NOTEST -bench=Medium . && \
		$(GO) test $(LDFLAGS) -tags rocksdb,pebbledb -run=NOTEST -timeout=30m -bench=Large . && \
		$(GO) test $(LDFLAGS) -run=NOTEST -bench=Mem . && \
		$(GO) test $(LDFLAGS) -run=NOTEST -timeout=60m -bench=LevelDB .
.PHONY: fullbench

# note that this just profiles the in-memory version, not persistence
profile:
	cd benchmarks && \
		$(GO) test $(LDFLAGS) -bench=Mem -cpuprofile=cpu.out -memprofile=mem.out . && \
		$(GO) tool pprof ${PDFFLAGS} benchmarks.test cpu.out > cpu.pdf && \
		$(GO) tool pprof --alloc_space ${PDFFLAGS} benchmarks.test mem.out > mem_space.pdf && \
		$(GO) tool pprof --alloc_objects ${PDFFLAGS} benchmarks.test mem.out > mem_obj.pdf
.PHONY: profile

explorecpu:
	cd benchmarks && \
		$(GO) tool pprof benchmarks.test cpu.out
.PHONY: explorecpu

exploremem:
	cd benchmarks && \
		$(GO) tool pprof --alloc_objects benchmarks.test mem.out
.PHONY: exploremem

delve:
	dlv test ./benchmarks -- -test.bench=.
.PHONY: delve
