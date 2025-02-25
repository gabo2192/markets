# Include environment variables from the selected environment file
-include .env.$(ENV)

# Default to local environment if not specified
RPC_URL ?= http://localhost:8545
PK ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

.PHONY: all test clean build help install update \
        deploy-ctf-exchange deploy-oracle-resolver deploy-market-creator deploy-all

help:
	@echo "Available commands:"
	@echo "  make install                - Install dependencies"
	@echo "  make update                 - Update dependencies"
	@echo "  make build                  - Build the contracts"
	@echo "  make test                   - Run all tests"
	@echo "  make test-verbose           - Run all tests with verbose output"
	@echo "  make test-market            - Run only market creation tests"
	@echo "  make clean                  - Remove build artifacts"
	@echo "  make deploy-ctf-exchange    - Deploy the CTFExchange from DeployCTFExchange.s.sol"
	@echo "  make deploy-oracle-resolver - Deploy OracleResolver from DeployOracleResolver.s.sol"
	@echo "  make deploy-market-creator  - Deploy MarketCreator from DeployMarketCreator.s.sol"
	@echo "  make deploy-all             - Deploy all main contracts from DeployAll.s.sol"

# Installation
install:
	forge install --no-commit

update:
	forge update

# Building
build:
	forge build

# Testing
test:
	forge test -vv

test-verbose:
	forge test -vvv

test-market:
	forge test --match-contract MarketCreatorTest -vv

# Clean up
clean:
	forge clean

# --------------------------------------------------------------------------------
#  Single-purpose deployment targets for the new scripts
# --------------------------------------------------------------------------------

deploy-ctf-exchange:
	@echo "Deploying CTFExchange via DeployCTFExchange.s.sol..."
	@if [ -z "$(PK)" ] || [ -z "$(RPC_URL)" ]; then \
		echo "Error: Missing required environment variables (PK, RPC_URL)."; \
		exit 1; \
	fi
	forge script script/DeployCTFExchange.s.sol:DeployCTFExchange \
		--rpc-url $(RPC_URL) \
		--private-key $(PK) \
		--broadcast

deploy-oracle-resolver:
	@echo "Deploying OracleResolver via DeployOracleResolver.s.sol..."
	@if [ -z "$(PK)" ] || [ -z "$(RPC_URL)" ]; then \
		echo "Error: Missing required environment variables (PK, RPC_URL)."; \
		exit 1; \
	fi
	forge script script/DeployOracleResolver.s.sol:DeployOracleResolver \
		--rpc-url $(RPC_URL) \
		--private-key $(PK) \
		--broadcast

deploy-market-creator:
	@echo "Deploying MarketCreator via DeployMarketCreator.s.sol..."
	@if [ -z "$(PK)" ] || [ -z "$(RPC_URL)" ]; then \
		echo "Error: Missing required environment variables (PK, RPC_URL)."; \
		exit 1; \
	fi
	forge script script/DeployMarketCreator.s.sol:DeployMarketCreator \
		--rpc-url $(RPC_URL) \
		--private-key $(PK) \
		--broadcast

deploy-all:
	@echo "Deploying all main contracts via DeployAll.s.sol..."
	@if [ -z "$(PK)" ] || [ -z "$(RPC_URL)" ]; then \
		echo "Error: Missing required environment variables (PK, RPC_URL)."; \
		exit 1; \
	fi
	forge script script/DeployAll.s.sol:DeployAll \
		--rpc-url $(RPC_URL) \
		--private-key $(PK) \
		--broadcast

# Default
all: clean build test
