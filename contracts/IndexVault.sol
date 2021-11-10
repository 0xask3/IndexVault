//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./IterableMapping.sol";

contract IndexVault is Ownable {
    using IterableMapping for IterableMapping.Map;

    IERC20 public token; //deposit token
    uint256 public totalAllocation; //Total allocation points

    IterableMapping.Map private AssetsMap;

    IUniswapV2Router02 private router =
        IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);   

    mapping(address => uint256) public depositAmount;
    mapping(address => mapping(address => uint256)) public investors;

    uint256 public totalDeposits;
    uint256 private constant divisor = 1000;

    constructor(
        address _token,
        address[] memory assets,
        uint256[] memory allocations
    ) {
        token = IERC20(_token);
        uint256 len = assets.length;
        require(len == allocations.length, "Incorrect input");

        for (uint256 i = 0; i < len; i++) {
            AssetsMap.set(assets[i], allocations[i]);
            totalAllocation += allocations[i];
            IERC20(assets[i]).approve(address(router), ~uint256(0));
        }

        token.approve(address(router), ~uint256(0));
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);

        uint256 len = AssetsMap.size();
        depositAmount[msg.sender] += amount;
        totalDeposits += amount;

        address asset;
        uint256 allocation;
        uint256 initialBalance;
        uint256 finalBalance;

        for (uint256 i = 0; i < len; i++) {
            asset = AssetsMap.getKeyAtIndex(i);
            allocation = (amount * AssetsMap.get(asset)) / totalAllocation;

            initialBalance = IERC20(asset).balanceOf(address(this));
            swapTokenForAsset(asset, allocation);
            finalBalance =
                IERC20(asset).balanceOf(address(this)) -
                initialBalance;

            investors[msg.sender][asset] += finalBalance;
        }
    }

    function withdrawAssets(uint256 percentage, address withdrawAddress)
        external
    {
        require(depositAmount[msg.sender] > 0, "No active deposits");
        uint256 withdrawPercentage = (depositAmount[msg.sender] * percentage) /
            divisor;
        depositAmount[msg.sender] -= withdrawPercentage;
        totalDeposits -= withdrawPercentage;

        uint256 len = AssetsMap.size();
        address asset;
        uint256 amount;
        uint256 initialBalance = token.balanceOf(address(this));
        
        for (uint256 i = 0; i < len; i++) {
            asset = AssetsMap.getKeyAtIndex(i);
            amount = (investors[msg.sender][asset] * percentage) / divisor;

            swapAssetForToken(asset, amount);
            investors[msg.sender][asset] -= amount;
        }

        uint256 finalBalance = token.balanceOf(address(this)) - initialBalance;
        token.transfer(withdrawAddress, finalBalance);

    }

    function getTokenPrice(address _token, uint256 amount)
        internal
        view
        returns (uint256)
    {   
        address pairAddress = IUniswapV2Factory(router.factory()).getPair(router.WETH(),_token);

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint256 Res0, uint256 Res1, ) = pair.getReserves();

        return ((amount * Res0) / Res1); // return amount of token0 needed to buy token1
    }

    function getPricePerToken() public view returns (uint256 unitPrice) {
        uint256 totalPrice;
        uint256 len = AssetsMap.size();
        address asset;

        for (uint256 i = 0; i < len; i++) {
            asset = AssetsMap.getKeyAtIndex(i);
            totalPrice += getTokenPrice(asset,IERC20(asset).balanceOf(address(this)));
        }

        unitPrice = totalPrice / totalDeposits;     
    }

    function getTotalPriceOfUser(address user) public view returns (uint256 holdings) {
        holdings = depositAmount[user] * getPricePerToken();
    }

    function swapTokenForAsset(address asset, uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(token);
        path[1] = router.WETH();
        path[2] = asset;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAssetForToken(address asset, uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = asset;
        path[1] = router.WETH();
        path[2] = address(token);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function setAllocation(address asset, uint256 allocation)
        external
        onlyOwner
    {
        uint256 oldValue = AssetsMap.get(asset);
        if (oldValue == 0) {
            IERC20(asset).approve(address(router), ~uint256(0));
        }
        AssetsMap.set(asset, allocation);
        totalAllocation = totalAllocation + allocation - oldValue;
    }

    function setToken(address newToken) external onlyOwner {
        token = IERC20(newToken);
        token.approve(address(router), ~uint256(0));
    }
}
