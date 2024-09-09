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

### Test coverage:
```bash
make coverage
```
Visual line coverage report with LCOV.
It is required to install lcov.
```bash
brew install lcov
```
To run the coverage report, the below command can be executed.
```bash
forge coverage --report lcov
LCOV_EXCLUDE=('src/interfaces/*' 'test/*' 'script/*')
lcov --remove lcov.info ${LCOV_EXCLUDE[@]} --output-file lcov-filtered.info --rc lcov_branch_coverage=1
genhtml lcov-filtered.info --branch-coverage --output-directory out/coverage
open out/coverage/index.html
```

## Contracts on Ethereum Sepolia Testnet:

| Name             | Address                                                                                                                       |
| :--------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| EscrowFixedPrice | [0xB3A88448768aa314bAdbE43A5d394B1B8Ef2db1b](https://sepolia.etherscan.io/address/0xB3A88448768aa314bAdbE43A5d394B1B8Ef2db1b) |
| EscrowMilestone  | [0x833cb00a77A82797de64C7453fE235CA369410Dc](https://sepolia.etherscan.io/address/0x833cb00a77A82797de64C7453fE235CA369410Dc) |
| EscrowHourly     | [0x2847A804d24d10a43E765873fc3a670c3b35937A](https://sepolia.etherscan.io/address/0x2847A804d24d10a43E765873fc3a670c3b35937A) |
| Factory          | [0xE5552A5830cd05a3f19553A8879582C33E9E46D8](https://sepolia.etherscan.io/address/0xE5552A5830cd05a3f19553A8879582C33E9E46D8) |
| EscrowRegistry   | [0x928D26474d15855c697F47A64f8877b228920d59](https://sepolia.etherscan.io/address/0x928D26474d15855c697F47A64f8877b228920d59) |
| AdminManager     | [0xaDfE561EE14842D05a7720a4d9Eb2579891f3D67](https://sepolia.etherscan.io/address/0xaDfE561EE14842D05a7720a4d9Eb2579891f3D67) |
| FeeManager       | [0x617247BCcDB41F55AdbE31234b2a8aC273b57c35](https://sepolia.etherscan.io/address/0x617247BCcDB41F55AdbE31234b2a8aC273b57c35) |
| AccountRecovery  | [0x09684b2C9c835198122dBeecE729c202758fE3e6](https://sepolia.etherscan.io/address/0x09684b2C9c835198122dBeecE729c202758fE3e6) |

## Licensing

The primary license for the Midcontract platform is MIT, see [`LICENSE`](LICENSE)
