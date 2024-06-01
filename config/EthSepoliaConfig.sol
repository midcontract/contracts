// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Latest configuration of deployed contracts
library EthSepoliaConfig {
    uint256 public constant CHAIN_ID = 11155111;

    address public constant REGISTRY = 0xcda8DF73fFA90c151879F0E5A46B2ad659502C73; //0x8C2603DCdD7a94d5f7312235dcd5CEc98B80e3Cd;
    address public constant MOCK_DAI = 0xD52154bd4b275D7D6059D68A730003E5E85F42b6;
    address public constant MOCK_USDT = 0xa801061f49970Ef796e0fD0998348f3436ccCb1d;
    address public constant ESCROW = 0x5C42320Ea8711E3fB811e136d87fe9a6B4d02025; //0x7369e88CA0e58Db31185759c1B3199d8e4E4aC8b;
    address public constant FACTORY = 0xE732a3625499885cE800f795A076C6Daf69e9E3d; //0xa01F06ceC1f7Bf6864678940313740FDffCAdbE9;
    address public constant FEE_MANAGER = 0xA4857B1178425cfaaaeedBcFc220F242b4A518fA;
    address public constant ESCROW_PROXY = 0xEAC34764333F697c31a7C72ee74ED33D1dEfff0d; //0x6ADD42010309a1A38D2D61bcBC7124863544B690;
}