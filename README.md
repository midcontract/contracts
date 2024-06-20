# <h1 align="center"> Midcontract Platform Contracts </h1>

<h3 align="center"> This repository contains the smart contract suite used in Midcontract project </h3>
<br>

## Getting Started

### Install Foundry and Forge: [installation guide](https://book.getfoundry.sh/getting-started/installation)

## Usage

### Setup:
```bash
git clone <repo_link>
```
### Install dependencies:
```bash
forge install
```

### Compile contracts:
```bash
make build
```
### Run unit tests:
```bash
make test
```
### Add required .env variables:
```bash
cp .env.example .env
```
### Deploy contracts:
```bash
make deploy-escrow
```

## Contracts on Ethereum Sepolia Testnet:
| Name | Address |
| :--- | :--- |
| Escrow | [0xdF26423aa64eA4742209A1c52bBfe9dD0ab6D5B5](https://sepolia.etherscan.io/address/0xdF26423aa64eA4742209A1c52bBfe9dD0ab6D5B5) |
| Escrow Milestone | [0x9fD178b75AE324B573f8A8a21a74159375F383c5](https://sepolia.etherscan.io/address/0x9fD178b75AE324B573f8A8a21a74159375F383c5) |
| Escrow Hourly | [0x9161479c7Edb38D752BD17d31782c49784F52706](https://sepolia.etherscan.io/address/0x9161479c7Edb38D752BD17d31782c49784F52706) |
| Factory | [0xeaD5265B6412103d316b6389c0c15EBA82a0cbDa](https://sepolia.etherscan.io/address/0xeaD5265B6412103d316b6389c0c15EBA82a0cbDa) |
| Registry | [0xB536cc39702CE1103E12d6fBC3199cFC32d714f3](https://sepolia.etherscan.io/address/0xB536cc39702CE1103E12d6fBC3199cFC32d714f3) |
| FeeManager | [0xA4857B1178425cfaaaeedBcFc220F242b4A518fA](https://sepolia.etherscan.io/address/0xa4857b1178425cfaaaeedbcfc220f242b4a518fa) |
| Mock USDT | [0xa801061f49970Ef796e0fD0998348f3436ccCb1d](https://sepolia.etherscan.io/address/0xa801061f49970Ef796e0fD0998348f3436ccCb1d) |


## Licensing
The primary license for the Midcontract platform is MIT, see [`LICENSE`](LICENSE)
