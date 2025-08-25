// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    mapping(address => bool) public blacklisted;

    /**
     * @notice Constructor to initialize the Presale contract.
     * @param usdtAddress_ Address of the USDT token.
     * @param usdcAddress_ Address of the USDC token.
     * @param fundsReceiverAddress_ Address to receive the funds.
     * @param maxSellingAmount_ Maximum amount allowed for sale.
     * @param phases_ Array containing the phases configuration.
     */
    constructor(
        address usdtAddress_,
        address usdcAddress_,
        address fundsReceiverAddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        uint256[][3] memory phases_
    ) Ownable(msg.sender) {
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;

        require(endingTime_ > startingTime_, "Incorrect presale times");
    }

    /**
     * @notice Adds an address to the blacklist.
     * @dev Only callable by the contract owner.
     * @param user_ Address to be blacklisted.
     */
    function blackList(address user_) onlyOwner() external {
        blackList[user_] = true;
    }

    /**
     * @notice Removes an address from the blacklist.
     * @dev Only callable by the contract owner.
     * @param user_ Address to be removed from the blacklist.
     */
    function removeBlackList(address user_) onlyOwner() external {
        blackList[user_] = false;
    }

    /**
     * @notice Allows a user to buy with stable coins if not blacklisted.
     * @dev Checks if the user is not blacklisted before proceeding.
     */
    function buyWithStable() external {
        require(!blackList[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale is not active");
    }

    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) onlyOwner() external {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyETHWithdraw() onlyOwner() external {
        uint256 balance = address(this).balance;
        (bool success,) =msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
    }
}