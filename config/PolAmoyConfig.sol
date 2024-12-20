// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Latest configuration of deployed contracts
library PolAmoyConfig {
    uint256 public constant CHAIN_ID = 80002;

    // BETA
    address public constant ESCROW_FIXED_PRICE = 0x6c71098e924D99Ad6D91A48591cD3ae67a2583d6; //0xf26D105Ffa6Cb592Cc531218FCE5c6b9F3Fc4fe1;
    address public constant ESCROW_MILESTONE = 0x81284Ed6Ef89eCaae6D110d07280866c4A2FEC62; //0x0f2bB056a862C1576ce387803a828ca065687f29;
    address public constant ESCROW_HOURLY = 0xd06378ac34C64f1E32CeD460BB5ceAD25F2620Cb; //0xd3e782ecB258824Aa5C0dC692472f4d6c761B2Dc;
    address public constant FACTORY = 0x7cdFBb8867450F3791ce79Dc41b0027b6de5943f; //0x704760EA333633DD875aA327c9e6cFba7b3bDA4a;

    address public constant REGISTRY = 0x043b15159a4210Dd884e254FA794ECF6ae8449b3; //0xf2f8bb2549313Ca95D4cE688C76b713e2D31E4E7;
    address public constant FEE_MANAGER = 0x06D2c7002b78dFFabdF32f3650d4F1100d4C413D; //0x0D642fB93036cC33455d971e3E74eF712B433b90;

    // DEV
    address public constant ESCROW_FIXED_PRICE_1 = 0x803DFC1fBB4Ba3A6eB9603eDe2458b5F62C117a8; //0x4De255Fb29f4FBF87EDAFA344da1712DCc7B3323;
    address public constant ESCROW_MILESTONE_1 = 0xae146D824c08F45BDf34741D3b50F4Fb1104E79f; //0x2D789b9133e5a88d64Ed6b17Cf6443a1FC8bfce3;
    address public constant ESCROW_HOURLY_1 = 0xD0E424C9ebda1D635cFDFB11Ac10303C148F5049; //0xd7f4431FD41a31F91a29eC56238CD3FB5465E1df;
    address public constant FACTORY_1 = 0xE2B05184705A5b25De95DcEc77147B93B4a26f31; //0xA2681a0C44BC818D51618a41b1761B54972f92ba;

    address public constant REGISTRY_1 = 0x17EB9587525A4CdD60A06375f1F5ba9d69684198; //0xa09d32E9330ebcdeC3635845E0a5BC056149064e;
    address public constant FEE_MANAGER_1 = 0x9FAb81E260be5A5cD7371D6227a004Ce219C46F5; //0x311fCF7F01bf49836c4e1E43FD44fE4921B00e6a;

    // COMMON
    address public constant ACCOUNT_RECOVERY = 0xC4F460ED012c71Ec78392bdf6b983fBbDEB38a6d; //0x7a2A0632AeCB0eDE68a4c498CEa2cf93abD4bdA4;
    address public constant ADMIN_MANAGER = 0x501cbBCa63ea1f0cc9a490A33B60f08eCD2DAB27; //0x1db3e13120498872930F86836B7757056617eF5F;
    address public constant OWNER = 0x3eAb900aC1E0de25F465c63717cD1044fF69243C; // INITIAL OWNER/ADMIN
    address public constant MOCK_USDC = 0x2AFf4E62eC8A5798798a481258DE66d88fB6bbCb;
    address public constant MOCK_USDT = 0xD19AC10fE911d913Eb0B731925d3a69c80Bd6643;
    address public constant MOCK_DAI = 0xA0A8Ee7bF502EC4Eb5C670fE5c63092950dbB718;
}
