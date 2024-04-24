// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Latest configuration of deployed contracts
library EthSepoliaConfig {
    uint256 public constant CHAIN_ID = 11155111;

    address public constant REGISTRY = 0x8C2603DCdD7a94d5f7312235dcd5CEc98B80e3Cd;
    address public constant MOCK_PAYMENT_TOKEN = 0x288f4508660A747C77A95D68D5b77eD89CdE9D03;
    address public constant ESCROW = 0x9904951133E96a2330A5862E0B87E810437C2cC0;
    address public constant FACTORY = 0xa01F06ceC1f7Bf6864678940313740FDffCAdbE9;
    address public constant ESCROW_PROXY = 0x6add42010309a1a38d2d61bcbc7124863544b690;
}