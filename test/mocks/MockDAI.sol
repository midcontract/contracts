// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

contract MockDAI is ERC20 {
    constructor() ERC20("MockDAI", "MockDAI", 18) {}

    function claim() external {
        _mint(msg.sender, 1000 ether);
    }

    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(address from, uint256 value) public returns (bool) {
        _burn(from, value);
        return true;
    }
}
