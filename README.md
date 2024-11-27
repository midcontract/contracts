<h1> Midcontract </h1>

<br>

[![Tests](https://github.com/midcontract/contracts/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/midcontract/contracts/actions/workflows/test.yml) ![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg) ![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)


## Overview
This repository contains the Smart Contract Project for a comprehensive escrow system designed to handle various types of agreements, including fixed-price, hourly, and milestone-based contracts. The system is structured to facilitate secure and transparent transactions between parties, ensuring compliance and trust through programmable escrow logic.

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
| EscrowFixedPrice | [0x6c71098e924D99Ad6D91A48591cD3ae67a2583d6](https://amoy.polygonscan.com/address/0x6c71098e924D99Ad6D91A48591cD3ae67a2583d6) |
| EscrowHourly     | [0xd3e782ecB258824Aa5C0dC692472f4d6c761B2Dc](https://amoy.polygonscan.com/address/0xd3e782ecB258824Aa5C0dC692472f4d6c761B2Dc) |
| EscrowMilestone  | [0x0f2bB056a862C1576ce387803a828ca065687f29](https://amoy.polygonscan.com/address/0x0f2bB056a862C1576ce387803a828ca065687f29) |
| EscroFactory          | [0x7cdFBb8867450F3791ce79Dc41b0027b6de5943f](https://amoy.polygonscan.com/address/0x7cdFBb8867450F3791ce79Dc41b0027b6de5943f) |
| EscroRegistry   | [0x043b15159a4210Dd884e254FA794ECF6ae8449b3](https://amoy.polygonscan.com/address/0x043b15159a4210Dd884e254FA794ECF6ae8449b3) |
| AdminManager     | [0x501cbBCa63ea1f0cc9a490A33B60f08eCD2DAB27](https://amoy.polygonscan.com/address/0x501cbBCa63ea1f0cc9a490A33B60f08eCD2DAB27) |
| FeeManager       | [0x06D2c7002b78dFFabdF32f3650d4F1100d4C413D](https://amoy.polygonscan.com/address/0x06D2c7002b78dFFabdF32f3650d4F1100d4C413D) |
| AccountRecovery  | [0xC4F460ED012c71Ec78392bdf6b983fBbDEB38a6d](https://amoy.polygonscan.com/address/0xC4F460ED012c71Ec78392bdf6b983fBbDEB38a6d) |

## Licensing

The primary license for the Midcontract project is MIT, see [`LICENSE`](LICENSE)
