<h1> Midcontract </h1>

<br>

[![Tests](https://github.com/midcontract/contracts/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/midcontract/contracts/actions/workflows/test.yml) ![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg) ![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)


## Overview
This repository contains the Smart Contract Project for a comprehensive escrow system designed to handle various types of agreements, including fixed-price, hourly, and milestone-based contracts. The system is structured to facilitate secure and transparent transactions between parties, ensuring compliance and trust through programmable escrow logic.

## Documentation
For detailed information about the smart contracts, see the [Docs](docs/src/SUMMARY.md).

## Key Features
1. **Versatile Contract Types:** Supports various types of escrow agreements:
   - **Fixed-Price:** For straightforward, one-off payments upon job completion.
   - **Hourly:** For ongoing work with automated weekly billing based on recorded hours.
   - **Milestone:** For complex projects with payments divided into specific goals or stages.

2. **Robust Security Features:**
   - **Account Recovery:** Enhances security by allowing for the recovery of contractor accounts, providing a backup mechanism in case of access issues.
   - **Admin-Controlled Operations:** The EscrowAdminManager facilitates critical operations like dispute resolution and account recovery, ensuring that they are executed under strict oversight.

3. **Automated Fee Management:**
   - **Dynamic Fee Calculation:** The EscrowFeeManager automates the calculation of transaction fees based on preset rules, ensuring transparency and fairness in fee distribution.
   - **Fee Optimization:** Implements strategies to minimize transaction costs and optimize fee structures for all parties involved.

4. **Comprehensive Tracking and Management:**
   - **EscrowRegistry:** Serves as a comprehensive hub for all escrow contracts, offering robust tools for management and seamless audit capabilities. It ensures that contract data is uniformly maintained and easily accessible, simplifying compliance and audit activities by providing a reliable and consistent dataset.

5. **Modular and Extensible:**
   - **Interchangeable Components:** The system’s modular design allows for components to be added, removed, or replaced without disrupting the core functionality, facilitating easy updates and customization.
   - **Interface-Driven Interactions:** Interfaces ensure that despite the modular nature, all components communicate effectively, maintaining a consistent workflow across different contract types and modules.

6. **Event-Driven Notifications:**
   - **Real-Time Updates:** Events are emitted for every significant action, from deposits to withdrawals and dispute resolutions, enabling real-time tracking and response by users and external systems.

7. **Dispute Resolution:**
   - **Structured Dispute Handling:** Provides a clear framework for initiating, managing, and resolving disputes, with predefined roles and processes to ensure fairness and efficiency.
   - **Support for Multiple Resolution Outcomes:** Handles different outcomes like full refunds, partial settlements, or contractor completions based on the nature of the dispute.

## Getting Started

### Install Foundry and Forge: [installation guide](https://book.getfoundry.sh/getting-started/installation)

## Local Development

### Install Dependencies:

```bash
forge install
```

### Compile Contracts:

```bash
make build
```

### Run Tests:

```bash
make test
```

### Test Coverage:

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

## Contracts on Polygon Amoy Testnet:

| Name             | Address                                                                                                                       |
| :--------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| EscroFactory     | [0xE2B05184705A5b25De95DcEc77147B93B4a26f31](https://amoy.polygonscan.com/address/0xE2B05184705A5b25De95DcEc77147B93B4a26f31) |
| EscrowFixedPrice | [0x803DFC1fBB4Ba3A6eB9603eDe2458b5F62C117a8](https://amoy.polygonscan.com/address/0x803DFC1fBB4Ba3A6eB9603eDe2458b5F62C117a8) |
| EscrowHourly     | [0xD0E424C9ebda1D635cFDFB11Ac10303C148F5049](https://amoy.polygonscan.com/address/0xD0E424C9ebda1D635cFDFB11Ac10303C148F5049) |
| EscrowMilestone  | [0xae146D824c08F45BDf34741D3b50F4Fb1104E79f](https://amoy.polygonscan.com/address/0xae146D824c08F45BDf34741D3b50F4Fb1104E79f) |
| EscroRegistry    | [0x17EB9587525A4CdD60A06375f1F5ba9d69684198](https://amoy.polygonscan.com/address/0x17EB9587525A4CdD60A06375f1F5ba9d69684198) |
| AdminManager     | [0x501cbBCa63ea1f0cc9a490A33B60f08eCD2DAB27](https://amoy.polygonscan.com/address/0x501cbBCa63ea1f0cc9a490A33B60f08eCD2DAB27) |
| AccountRecovery  | [0xC4F460ED012c71Ec78392bdf6b983fBbDEB38a6d](https://amoy.polygonscan.com/address/0xC4F460ED012c71Ec78392bdf6b983fBbDEB38a6d) |
| FeeManager       | [0x9FAb81E260be5A5cD7371D6227a004Ce219C46F5](https://amoy.polygonscan.com/address/0x9FAb81E260be5A5cD7371D6227a004Ce219C46F5) |

## Licensing

The primary license for the Midcontract project is MIT, see [`LICENSE`](LICENSE)
