// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IAggregator.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    address public saleTokenAddress;
    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    address public dataFeedAddress;
    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    uint256 public totalSold;
    uint256 public currentPhase;
    mapping(address => bool) public blackList;
    mapping(address => uint256) public userTokenBalance;

    event TokenBuy(address user, uint256 amount);

    /**
     * @notice Constructor to initialize the Presale contract.
     * @param usdtAddress_ Address of the USDT token.
     * @param usdcAddress_ Address of the USDC token.
     * @param fundsReceiverAddress_ Address to receive the funds.
     * @param maxSellingAmount_ Maximum amount allowed for sale.
     * @param phases_ Array containing the phases configuration.
     */
    constructor(
        address saleTokenAddress_,
        address usdtAddress_,
        address usdcAddress_,
        address fundsReceiverAddress_,
        address dataFeedAddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        uint256[][3] memory phases_
    ) Ownable(msg.sender) {
        saleTokenAddress = saleTokenAddress_;
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        dataFeedAddress = dataFeedAddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;

        require(endingTime_ > startingTime_, "Incorrect presale times");
        IERC20(saleTokenAddress_).safeTransferFrom(msg.sender, address(this), maxSellingAmount_);
    }

    /**
     * @notice Adds an address to the blacklist.
     * @dev Only callable by the contract owner.
     * @param user_ Address to be blacklisted.
     */
    function addToBlackList(address user_) onlyOwner() external {
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

    function checkCurrentPhase(uint256 amount_) private returns(uint256 phase) {
        if((totalSold + amount_ >= phases[currentPhase][0] || (block.timestamp >= phases[currentPhase][2])) && currentPhase < 3) {
            currentPhase++;
        } else {
            phase = currentPhase;
        }
    }

    /**
     * @notice Allows a user to buy with stable coins if not blacklisted.
     * @dev Checks if the user is not blacklisted before proceeding.
     * @param tokenUsedToBuy_ The address of the stable coin used for purchase.
     * @param amount_ The amount of stable coin to be used for purchase.
     */
    function buyWithStable(address tokenUsedToBuy_, uint256 amount_) external {
        require(!blackList[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale is not active");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Invalid stable coin");

        uint256 tokenAmountToReceive;
        if(ERC20(tokenUsedToBuy_).decimals() == 18) tokenAmountToReceive = amount_ * 1e6 / phases[currentPhase][1];
        else tokenAmountToReceive = amount_  * 10**(18 - ERC20(tokenUsedToBuy_).decimals()) * 1e6 / phases[currentPhase][1];
        checkCurrentPhase(tokenAmountToReceive);
        
        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Exceeds max selling amount");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);
        emit TokenBuy(msg.sender, amount_);
    }

    function buyWithEther() external payable{
        require(!blackList[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale is not active");

        uint256 usdValue = msg.value * getEtherPrice() / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase][1];
        checkCurrentPhase(tokenAmountToReceive);
        
        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Exceeds max selling amount");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        (bool success, ) = fundsReceiverAddress.call{value: msg.value}("");
        require(success, "Transfer fail");

        emit TokenBuy(msg.sender, tokenAmountToReceive);
    }

    function claim() external {
        require(block.timestamp > endingTime, "Presale not ended");
        uint256 amount = userTokenBalance[msg.sender];
        delete userTokenBalance[msg.sender];

        IERC20(saleTokenAddress).safeTransfer(msg.sender, amount);
    }

    function getEtherPrice() public view returns(uint256) {
        (,int256 price,,,) = IAggregator(dataFeedAddress).latestRoundData();
        price = price * ( 10**10);
        return uint256(price);
    }


    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) onlyOwner() external {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyETHWithdraw() onlyOwner() external {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
    }
}