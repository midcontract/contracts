// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Latest configuration of deployed contracts
library EthSepoliaConfig {
    uint256 public constant CHAIN_ID = 11155111;

    address public constant ESCROW = 0xD8038Fae596CDC13cC9b3681A6Eb44cC1984D670; //0xdF26423aa64eA4742209A1c52bBfe9dD0ab6D5B5;
    address public constant ESCROW_MILESTONE = 0x9fD178b75AE324B573f8A8a21a74159375F383c5;
    address public constant ESCROW_HOURLY = 0xaB870304768EDf45Bf425dAD11487176FbF88762; //0x44096F936213A9d94E7Fe5110d4Ed7B69F0331EA;
    address public constant FACTORY = 0xeaD5265B6412103d316b6389c0c15EBA82a0cbDa; //0xE732a3625499885cE800f795A076C6Daf69e9E3d;
    address public constant REGISTRY = 0xB536cc39702CE1103E12d6fBC3199cFC32d714f3; //0xcda8DF73fFA90c151879F0E5A46B2ad659502C73;
    address public constant FEE_MANAGER = 0xA4857B1178425cfaaaeedBcFc220F242b4A518fA;
    address public constant ESCROW_PROXY = 0xEAC34764333F697c31a7C72ee74ED33D1dEfff0d; //0x6ADD42010309a1A38D2D61bcBC7124863544B690;
    address public constant OWNER = 0x3eAb900aC1E0de25F465c63717cD1044fF69243C; // ADMIN
    address public constant MOCK_USDT = 0xa801061f49970Ef796e0fD0998348f3436ccCb1d;
    address public constant MOCK_DAI = 0xD52154bd4b275D7D6059D68A730003E5E85F42b6;
}