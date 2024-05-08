// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IERC721} from "openzeppelin/interfaces/IERC721.sol";



contract NFTAMMHook is ERC20, BaseHook {

    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address collection;

    uint256 private constant ONE = 1e18; // 1 eth
    uint256 private constant BASE = 100000; // Base for 1.0001 represented as 1.0001 * 10^5 for precision
    uint256 private constant ONE_HUNDRED = 100;  // For percentage calculations


    struct MMOrder {
        //the price at which this order will start selling nfts
        int24 startingSellTick;
        //the price at which this order is willing to start purchasing nfts on the curve
        int24 startingBuyTick;
        //tracking the current price as it moves along the bond curve
        int24 currentTick;
        //the eth that will be deposited to cover the buy orders
        uint256 ethBalance;
        // the maximum amount of nfts that the order is willing to purchase
        uint256 maxNumOfNFTs;
        //the percentage change at which the sell/buy orders will change. i.e. "steps". sell high buy low
        uint256 delta;
        //the swap fee on this order for either buying or selling into the order. money is made here
        uint256 fee;
        //collection address of the order
        address nftAddress;
    }


    mapping(uint256 => uint160) public tokenIdsToSqrtRatio;

    //mapping makers to their orders. multiple orders can be made
    mapping(address => mapping(uint256 id => MMOrder)) public makersToOrders;

    // the wNFT balances of the makers who have made orders
    mapping(address => uint256) public makerBalances;
    //order id is the current orderCount
    uint256 public orderId;


    constructor(IPoolManager _manager,
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _collection,
        uint8 decimals) BaseHook(_manager) ERC20(name, symbol, decimals) {
        orderId = 0;
        collection = _collection;
        _mint(address(this), initialSupply);
}




    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    // @notice creating the market making order. A bid on the collection to both buy and sell nfts on a bond curve
    // @param _nftAddress  address of the nft collection
    // @param startingBuyTick  starting price to begin purchasing nfts
    // @param startingSellTick starting price at which they will sell their nfts
    // @param tokenIds of the nfts being sold
    // @param delta the percent by which every order will change on the bond curve
    // @param fee the fee at which the maker will charge on their trades to be profitable
    // @param maxNumOfNFTs the maximum numOfNFTs that the buyer is willing to purchase
    function marketMake(
        address _nftAddress,
        int24 startingBuyTick,
        int24 startingSellTick,
        uint256[] calldata tokenIds,
        uint256 delta,
        uint256 fee,
        uint256 maxNumOfNFTs
    ) public payable {
        require(_nftAddress == collection);
        require(address(msg.sender) != address(0));

        //idea is to buy low sell high. selling tick needs to be slightly higher than buy tick
        require(startingSellTick > startingBuyTick);

        //checking whether there is enough eth deposited to cover their order
        require(isThereEnoughEth(startingSellTick, delta, maxNumOfNFTs, msg.value));

        orderId++;

        //creating the order
        MMOrder storage order = makersToOrders[msg.sender][orderId];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Calculate and assign the sqrt price for each token, given a number of NFTs, starting tick, and delta
            uint160 sqrtPriceX96 = createSqrtPriceForSingleToken(startingSellTick, delta, i);
            tokenIdsToSqrtRatio[tokenIds[i]] = sqrtPriceX96;
        }
        order.startingBuyTick = startingBuyTick;
        order.startingSellTick = startingSellTick;
        order.currentTick = startingSellTick;
        order.ethBalance = msg.value;
        order.maxNumOfNFTs = maxNumOfNFTs;
        order.delta = delta;
        order.fee = fee;
        order.nftAddress = _nftAddress;

        //transfer nfts to hook from order
        //mint wrapped tokens to user according to wei price
        for (uint256 i = 0; i < tokenIds.length; i++) {
        IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        //updating wrapped token share.user doesn't actually get the tokens so the hook has to supply liquidity for them
        determineWrappedTokenShare(TickMath.getSqrtRatioAtTick(startingSellTick), tokenIds, delta);
    }

    function determineWrappedTokenShare(uint160 sqrtPriceX96, uint256[] calldata tokenIds, uint256 delta) internal {
        // Convert sqrtPriceX96 to the actual price ratio (Token 0 per Token 1)
        uint256 priceRatio = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96; // Square and adjust from Q64.96

        // Calculate the total value of the NFTs being deposited, priced in Token 0 (ETH)
        uint256 totalValueInToken0 = 0;
        uint256 currentPriceInToken0 = priceRatio; // Start with the price of one NFT in Token 0

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalValueInToken0 += currentPriceInToken0;

            // Adjust the price for the next NFT based on the delta percentage
            currentPriceInToken0 = currentPriceInToken0 * (100 - delta) / 100;
        }

        // Calculate the equivalent amount in Ether, adjust for Q64.96 if necessary
        uint256 totalValueInEther = totalValueInToken0 / 1e18; // Assuming the priceRatio scales up to Wei correctly

        // Mint or assign the calculated Ether equivalent to the user's balance
        makerBalances[msg.sender] += totalValueInEther;
    }

    //TODO refactor this to have price change by sqrt not the tick
    function createSqrtPriceForSingleToken(int24 tick, uint256 delta, uint256 index) internal pure returns (uint160) {
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "Tick is out of range");

        int256 currentTick = tick;
        for (uint256 i = 0; i <= index; i++) {
            if (i != 0) {  // Skip the first iteration as no adjustment needed for the initial tick
                currentTick -= int256(delta);  // Decrease the tick by delta
                require(currentTick >= TickMath.MIN_TICK && currentTick <= TickMath.MAX_TICK, "Adjusted tick is out of range");
            }
        }

        // Convert the adjusted tick to a sqrt price ratio
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(currentTick));
        return sqrtPriceX96;
    }




    // Function to calculate the total price of `n` items, decreasing each subsequent item's price by `delta`.
    function totalDecreasingPrice(uint256 initialPriceInWei, uint256 delta, uint256 n) public pure returns (uint256) {
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
    function totalIncreasingPrice(uint256 initialPrice, uint256 delta, uint256 n) public pure returns (uint256) {
        uint256 totalPrice = 0;
        uint256 currentPrice = initialPrice;

        for (uint256 i = 0; i < n; i++) {
            totalPrice += currentPrice;
            // Increase the current price by `delta` percent
            currentPrice = currentPrice * (100 + delta) / 100;
        }

        return totalPrice;
    }



    function beforeSwap(address sender,
                        PoolKey calldata,
                        IPoolManager.SwapParams calldata, bytes calldata) external override virtual returns (bytes4) {
        // TODO - on before swap change allowance of msg.sender and swap on pool
        return this.beforeSwap.selector;
    }

    //on afterswap, burn tokens of swap, transfer nft to sender, transfer eth to seller
    function afterSwap(
                    address sender,
                    PoolKey calldata key,
                    IPoolManager.SwapParams calldata params,
                    BalanceDelta,
                    bytes calldata
                    ) external override poolManagerOnly returns (bytes4) {
        // TODO - on afterswap, burn tokens of swap, transfer nft to sender, transfer eth to seller
        return this.afterSwap.selector;
    }

    /// @notice Calculates the ETH price at a given tick using the TickMath library
    /// @param tick The tick at which to get the ETH price
    /// @return ethPrice The ETH price at the given tick
    function getEthPriceAtTick(int24 tick) public pure returns (uint256 ethPrice) {
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

    /// @notice Checks if the provided weiAmount is enough to cover the buy orders for a given number of NFTs on a bond curve.
    /// @param tick The starting tick for the first NFT
    /// @param delta The percentage decrease in price per NFT
    /// @param numberOfNFTs The number of NFTs to cover
    /// @param weiAmount The amount of wei provided to cover the orders
    /// @return sufficient A boolean indicating whether the provided wei is enough
    function isThereEnoughEth(int24 tick, uint256 delta, uint256 numberOfNFTs, uint256 weiAmount) public returns (bool sufficient) {
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
