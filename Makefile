-include .env

.PHONY: update build size inspect selectors test trace gas test-contract test-contract-gas trace-contract test-test trace-test clean snapshot anvil deploy

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

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

# Deploy to local environment
deploy-local :; forge script script/Escrow.s.sol:EscrowScript --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) -vvvv

# Deploy to Mumbai - Requires environment variables: MUMBAI_RPC_URL, DEPLOYER_EOA_PRIVATE_KEY, POLYGONSCAN_API_KEY
deploy-mumbai :; source .env && forge script script/Escrow.s.sol:EscrowScript --rpc-url $(MUMBAI_RPC_URL) --private-key $(DEPLOYER_EOA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(POLYGONSCAN_API_KEY) -vvvv