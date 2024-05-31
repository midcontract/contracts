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
| Escrow | [0x7369e88CA0e58Db31185759c1B3199d8e4E4aC8b](https://sepolia.etherscan.io/address/0x7369e88CA0e58Db31185759c1B3199d8e4E4aC8b) |
| Factory | [0xE732a3625499885cE800f795A076C6Daf69e9E3d](https://sepolia.etherscan.io/address/0xe732a3625499885ce800f795a076c6daf69e9e3d) |
| Registry | [0xcda8DF73fFA90c151879F0E5A46B2ad659502C73](https://sepolia.etherscan.io/address/0xcda8df73ffa90c151879f0e5a46b2ad659502c73) |
| FeeManager | [0xA4857B1178425cfaaaeedBcFc220F242b4A518fA](https://sepolia.etherscan.io/address/0xa4857b1178425cfaaaeedbcfc220f242b4a518fa) |
| Mock USDT | [0xa801061f49970Ef796e0fD0998348f3436ccCb1d](https://sepolia.etherscan.io/address/0xa801061f49970Ef796e0fD0998348f3436ccCb1d) |
| Escrow Proxy | [0xEAC34764333F697c31a7C72ee74ED33D1dEfff0d](https://sepolia.etherscan.io/address/0xeac34764333f697c31a7c72ee74ed33d1defff0d) |


## Licensing
The primary license for the Midcontract platform is MIT, see [`LICENSE`](LICENSE)
