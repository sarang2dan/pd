PD_PKG := github.com/pingcap/pd

TEST_PKGS := $(shell find . -iname "*_test.go" -exec dirname {} \; | \
                     uniq | sed -e "s/^\./github.com\/pingcap\/pd/")
BASIC_TEST_PKGS := $(filter-out github.com/pingcap/pd/pkg/integration_test,$(TEST_PKGS))

PACKAGES := go list ./...
PACKAGE_DIRECTORIES := $(PACKAGES) | sed 's|github.com/pingcap/pd/||'
GOCHECKER := awk '{ print } END { if (NR > 0) { exit 1 } }'
RETOOL:= ./hack/retool

GOFAIL_ENABLE  := $$(find $$PWD/ -type d | grep -vE "(\.git|vendor)" | xargs ./hack/retool do gofail enable)
GOFAIL_DISABLE := $$(find $$PWD/ -type d | grep -vE "(\.git|vendor)" | xargs ./hack/retool do gofail disable)

LDFLAGS += -X "$(PD_PKG)/server.PDReleaseVersion=$(shell git describe --tags --dirty)"
LDFLAGS += -X "$(PD_PKG)/server.PDBuildTS=$(shell date -u '+%Y-%m-%d %I:%M:%S')"
LDFLAGS += -X "$(PD_PKG)/server.PDGitHash=$(shell git rev-parse HEAD)"
LDFLAGS += -X "$(PD_PKG)/server.PDGitBranch=$(shell git rev-parse --abbrev-ref HEAD)"

# Ignore following files's coverage.
#
# See more: https://godoc.org/path/filepath#Match
COVERIGNORE := "cmd/*/*,pdctl/*,pdctl/*/*,server/api/bindata_assetfs.go"

default: build

all: dev

dev: build check test

ci: build check basic_test

build:
ifeq ("$(WITH_RACE)", "1")
	go build -race -ldflags '$(LDFLAGS)' -o bin/pd-server cmd/pd-server/main.go
else
	go build -ldflags '$(LDFLAGS)' -o bin/pd-server cmd/pd-server/main.go
endif
	go build -ldflags '$(LDFLAGS)' -o bin/pd-ctl tools/pd-ctl/main.go
	go build -o bin/pd-tso-bench tools/pd-tso-bench/main.go
	go build -o bin/pd-recover tools/pd-recover/main.go

test: retool-setup
	# testing..
	@$(GOFAIL_ENABLE)
	go test -race -cover $(TEST_PKGS) || { $(GOFAIL_DISABLE); exit 1; }
	@$(GOFAIL_DISABLE)

basic_test:
	@$(GOFAIL_ENABLE)
	go test $(BASIC_TEST_PKGS) || { $(GOFAIL_DISABLE); exit 1; }
	@$(GOFAIL_DISABLE)

# These need to be fixed before they can be ran regularly
check-fail:
	./hack/retool do gometalinter.v2 --disable-all \
	  --enable errcheck \
	  $$($(PACKAGE_DIRECTORIES))
	./hack/retool do gosec $$($(PACKAGE_DIRECTORIES))

check-all: static lint
	@echo "checking"

retool-setup:
	@which retool >/dev/null 2>&1 || go get github.com/twitchtv/retool
	@./hack/retool sync

check: retool-setup check-all

static:
	@ # Not running vet and fmt through metalinter becauase it ends up looking at vendor
	gofmt -s -l $$($(PACKAGE_DIRECTORIES)) 2>&1 | $(GOCHECKER)
	./hack/retool do govet --shadow $$($(PACKAGE_DIRECTORIES)) 2>&1 | $(GOCHECKER)

	./hack/retool do gometalinter.v2 --disable-all --deadline 240s \
	  --enable misspell \
	  --enable staticcheck \
	  --enable ineffassign \
	  $$($(PACKAGE_DIRECTORIES))

lint:
	@echo "linting"
	./hack/retool do revive -formatter friendly -config revive.toml $$($(PACKAGES))

travis_coverage:
ifeq ("$(TRAVIS_COVERAGE)", "1")
	GOPATH=$(VENDOR) $(HOME)/gopath/bin/goveralls -service=travis-ci -ignore $(COVERIGNORE)
else
	@echo "coverage only runs in travis."
endif

update:
	which dep 2>/dev/null || go get -u github.com/golang/dep/cmd/dep
ifdef PKG
	dep ensure -add ${PKG}
else
	dep ensure -update
endif
	@echo "removing test files"
	dep prune
	bash ./hack/clean_vendor.sh

simulator:
	go build -o bin/pd-simulator tools/pd-simulator/main.go

gofail-enable:
	# Converting gofail failpoints...
	@$(GOFAIL_ENABLE)

gofail-disable:
	# Restoring gofail failpoints...
	@$(GOFAIL_DISABLE)

.PHONY: update clean tool-install
