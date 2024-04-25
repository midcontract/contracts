# include .env file and export its env vars
# (-include to ignore error if it does not exist)
include .env

.PHONY: update build size inspect selectors test trace gas test-contract test-contract-gas trace-contract test-test trace-test clean snapshot anvil deploy

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Build & test
# deps
update :; forge update
build :; forge build
size :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty
# get the list of function selectors
selectors :; forge inspect ${contract} methods --pretty

# local tests without fork
test :; forge test -vvv
trace :; forge test -vvvv
gas :; forge test --gas-report
test-contract :; forge test -vvv --match-contract $(contract)
test-contract-gas :; forge test --gas-report --match-contract ${contract}
trace-contract :; forge test -vvvv --match-contract $(contract)
test-test :; forge test -vvv --match-test $(test)
trace-test :; forge test -vvvv --match-test $(test)

clean :; forge clean
snapshot :; forge snapshot

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# test with forks
# change ETH_RPC_URL to another one (e.g., FTM_RPC_URL) for different chains
FORK_URL := ${SEPOLIA_ALCHEMY_RPC_URL} 
test-fork :; source .env && forge test --match-contract EndToEndTest --rpc-url ${FORK_URL} -vvv

# Deploy to local environment
deploy-registry-local :; forge script script/deploy/01_DeployRegistry.s.sol:DeployRegistryScript --rpc-url http://localhost:8545 --private-key $(DEPLOYER_PRIVATE_KEY) -vvvv
deploy-escrow-local :; forge script script/deploy/02_DeployEscrow.s.sol:DeployEscrowScript --rpc-url http://localhost:8545 --private-key $(DEPLOYER_PRIVATE_KEY) -vvvv
deploy-factory-local :; forge script script/deploy/03_DeployEscrowFactory.s.sol:DeployEscrowFactoryScript --rpc-url http://localhost:8545 --private-key $(DEPLOYER_PRIVATE_KEY) -vvvv
execute-escrow-local :; forge script script/execute/ExecuteEscrow.s.sol:ExecuteEscrowScript --rpc-url http://localhost:8545 --private-key $(DEPLOYER_PRIVATE_KEY) -vvvv

# Deploy to Ethereum Sepolia - Requires environment variables: SEPOLIA_ALCHEMY_RPC_URL, DEPLOYER_PRIVATE_KEY, ETHERSCAN_API_KEY
deploy-registry-ethsepolia :; source .env && forge script script/deploy/01_DeployRegistry.s.sol:DeployRegistryScript --rpc-url ${SEPOLIA_ALCHEMY_RPC_URL} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv
deploy-escrow-ethsepolia :; source .env && forge script script/deploy/02_DeployEscrow.s.sol:DeployEscrowScript --rpc-url ${SEPOLIA_ALCHEMY_RPC_URL} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv
deploy-factory-ethsepolia :; source .env && forge script script/deploy/03_DeployEscrowFactory.s.sol:DeployEscrowFactoryScript --rpc-url ${SEPOLIA_ALCHEMY_RPC_URL} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv
execute-escrow-ethsepolia :; source .env && forge script script/execute/ExecuteEscrow.s.sol:ExecuteEscrowScript --rpc-url ${SEPOLIA_ALCHEMY_RPC_URL} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --gas-price 40000000000 --gas-limit ${GAS_LIMIT} -vvvv

# Deploy to Polygon Amoy
execute-escrow-amoy :; source .env && forge script script/execute/ExecuteEscrow.s.sol:ExecuteEscrowScript --rpc-url ${POLYGON_AMOY_RPC} --private-key ${DEPLOYER_PRIVATE_KEY} --gas-price 40000000000 --gas-limit ${GAS_LIMIT} -vvvv
