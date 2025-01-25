// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract MockFailingReceiver {
    receive() external payable {
        revert("ETH transfer failed");
    }
}