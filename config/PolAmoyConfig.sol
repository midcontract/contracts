// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Latest configuration of deployed contracts
library PolAmoyConfig {
    uint256 public constant CHAIN_ID = 80002;

    address public constant ESCROW_FIXED_PRICE = 0xA925686d8DA646854BF47b493C0f053ce62308C5;
    address public constant ESCROW_MILESTONE = 0xBa22c061905EfC35328ac6795e701d49F1e4fdB7;
    address public constant ESCROW_HOURLY = 0x17eB8F6B9e26C0Ab65bCED2dd044217d2425f6B3;
    address public constant FACTORY = 0x109F725FFda5020D6E4C9DEc83F07191e4a9632d;
    address public constant REGISTRY = 0x54d1bcB39ec52c21233Ac2ff745043487c832b76;
    address public constant FEE_MANAGER = 0x4FCe69069179559D28f607867ed6c708a799c7a5;
    address public constant OWNER = 0x3eAb900aC1E0de25F465c63717cD1044fF69243C; // ADMIN
    address public constant MOCK_USDT = 0xD19AC10fE911d913Eb0B731925d3a69c80Bd6643;
    address public constant MOCK_DAI = 0xA0A8Ee7bF502EC4Eb5C670fE5c63092950dbB718;
}