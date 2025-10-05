// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Mock token para simular el token de preventa
contract MockSaleToken is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {}
    
    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }
}