// NFTAMMLib.sol
pragma solidity ^0.8.0;

import {TickMath} from "v4-core/libraries/TickMath.sol";

library PriceLib {
    uint256 private constant ONE = 1e18; // 1 eth

    // Function to calculate the total price of `n` items, decreasing each subsequent item's price by `delta`.
    function totalDecreasingPrice(uint256 initialPriceInWei, uint256 delta, uint256 n) internal pure returns (uint256) {
        uint256 totalPrice = 0;
        uint256 currentPrice = initialPriceInWei;

        for (uint256 i = 0; i < n; i++) {
            totalPrice += currentPrice;
            // Decrease the current price by `delta` percent
            currentPrice = currentPrice * (100 - delta) / 100;
        }

        return totalPrice;
    }

    // Function to calculate the total price of `n` items, increasing each subsequent item's price by `delta`
    function totalIncreasingPrice(uint256 initialPrice, uint256 delta, uint256 n) internal pure returns (uint256) {
        uint256 totalPrice = 0;
        uint256 currentPrice = initialPrice;

        for (uint256 i = 0; i < n; i++) {
            totalPrice += currentPrice;
            // Increase the current price by `delta` percent
            currentPrice = currentPrice * (100 + delta) / 100;
        }

        return totalPrice;
    }

    // Calculates the ETH price at a given tick using the TickMath library
    function getEthPriceAtTick(int24 tick) internal pure returns (uint256 ethPrice) {
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "Tick is out of range");

        // Get the sqrtPriceX96 from the TickMath library
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        // Convert sqrtPriceX96 to the actual price ratio
        // priceRatio = (sqrtPriceX96^2) / 2^96
        uint256 priceRatio = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96;

        // Convert priceRatio to ETH value (adjusting for the Q64.96 format)
        ethPrice = priceRatio * ONE / 2**96;
        return ethPrice;
    }

    // Checks if the provided weiAmount is enough to cover the buy orders for a given number of NFTs on a bond curve.
    function isThereEnoughEth(int24 tick, uint256 delta, uint256 numberOfNFTs, uint256 weiAmount) internal view returns (bool sufficient) {
        require(weiAmount > 0, "NO ETH");
        uint256 totalCost = 0;
        uint256 currentPrice = getEthPriceAtTick(tick);

        for (uint256 i = 0; i < numberOfNFTs; i++) {
            totalCost += currentPrice;
            // Adjust the price for the next NFT based on the delta percentage
            // Delta is expected to be provided as a percentage, e.g., 5 for 5%
            currentPrice = currentPrice * (100 - delta) / 100;
        }

        // Check if the total wei provided covers the total cost
        sufficient = weiAmount >= totalCost;
        return sufficient;
    }
}