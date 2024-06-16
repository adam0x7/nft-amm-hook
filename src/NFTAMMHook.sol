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


import "forge-std/console.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";



contract NFTAMMHook is ERC20, BaseHook, IERC721Receiver {

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

    struct BidOrder {
        address maker;

        bool immediate;

        uint256 ethValue;

        uint256 bidId;

        int24 bidTick;

        uint256 orderId;
    }


    mapping(uint256 => uint160) public tokenIdsToSqrtRatio;

    //mapping makers to their orders. multiple orders can be made
    mapping(address => mapping(uint256 id => MMOrder)) public makersToOrders;

    // the wNFT balances of the makers who have made orders
    mapping(address => uint256) public makerBalances;
    //order id is the current orderCount
    uint256 public orderId;

    mapping(uint256 => address) public bidsToBuyers;


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
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
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
        require(_nftAddress == collection, "Collection is incorrect");
        require(address(msg.sender) != address(0), "msg.sender is not the zero address");

        //idea is to buy low sell high. selling tick needs to be slightly higher than buy tick
        require(startingSellTick > startingBuyTick, "sell tick is less than or equal to buy tick");

        //checking whether there is enough eth deposited to cover their order
        require(isThereEnoughEth(startingSellTick, delta, maxNumOfNFTs, msg.value), "there is not enough eth");

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
        console.log("SENDER BALANCE BEFORE HAND", IERC721(collection).balanceOf(address(msg.sender)));
        for (uint256 i = 0; i < tokenIds.length; i++) {
            console.log("tokens", tokenIds[i]);
                IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenIds[i]);

        }

        console.log("NFT BALANCE:" , IERC721(collection).balanceOf(address(this)));
        console.log("SENDER BALANCE:" , IERC721(collection).balanceOf(address(msg.sender)));
        //updating wrapped token share.user doesn't actually get the tokens so the hook has to supply liquidity for them
        determineWrappedTokenShare(TickMath.getSqrtRatioAtTick(startingSellTick), tokenIds, delta);

    }


    function createBuyBidOrder(uint256 _orderId, uint256 nftId, address _maker) external payable returns(bytes memory) {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        MMOrder storage order = makersToOrders[_maker][orderId];
        require(msg.value >= getEthPriceAtTick(order.currentTick), "Not tick equivalent or greater");

        BidOrder memory bidOrder = BidOrder(_maker, true, msg.value, nftId, order.currentTick, _orderId);

        bidsToBuyers[bidOrder.bidId] = msg.sender;
        return abi.encode(bidOrder);
    }

    function createSellOrder(uint256 _orderId, uint256 nftId, address _maker) external returns(bytes memory)  {
        // Find the latest collection bid and its current eth tick. This will determine how much eth needs to be transferred to the trader.
        MMOrder storage order = makersToOrders[_maker][_orderId];
        int24 currentTick = order.currentTick;

        // Transfer the NFT from the sender (seller) to the hook contract
        IERC721(collection).safeTransferFrom(msg.sender, address(this), nftId);

        // Create a sell order with the necessary information
        BidOrder memory sellOrder = BidOrder(_maker, true, getEthPriceAtTick(currentTick), nftId, currentTick, _orderId);
        bidsToBuyers[sellOrder.bidId] = msg.sender;

        return abi.encode(sellOrder);
    }

    fallback() external payable {}

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
        console.log("total eth value", totalValueInEther);
        makerBalances[msg.sender] += totalValueInEther;
    }

    function createSqrtPriceForSingleToken(int24 tick, uint256 delta, uint256 index) internal view returns (uint160) {
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "Tick is out of range");

        // Convert the initial tick to a sqrt price ratio
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        // Apply the percentage decrease for each subsequent token
        for (uint256 i = 0; i < index; i++) {
            // Calculate the new price as a percentage decrease
            uint256 reducedPrice = uint256(sqrtPriceX96) * (100 - delta) / 100;
            // Safely cast it back to uint160, assuming the result is within valid bounds
            sqrtPriceX96 = uint160(reducedPrice);
        }

        console.log("Final sqrt price", sqrtPriceX96);
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
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4) {
        console.log("AFTER SWAP HOOK HIT");
        // Decode the bidOrder from the calldata
        BidOrder memory bidOrder = abi.decode(hookData, (BidOrder));

        console.log("BID ORDER", bidOrder.ethValue);



            MMOrder storage order = makersToOrders[bidOrder.maker][bidOrder.orderId];

            if (params.zeroForOne) {
                // Buying NFTs (zeroForOne = true)
                // Transfer the NFT to the sender (buyer)
                IERC721(collection).safeTransferFrom(address(this), bidsToBuyers[bidOrder.bidId], bidOrder.bidId);

                // Transfer the Ether to the maker (seller)
                (bool success, ) = bidOrder.maker.call{value: bidOrder.ethValue}("");

                // Update the startingSellTick on the bonding curve
                uint160 currentSqrtPriceX96 = TickMath.getSqrtRatioAtTick(order.startingSellTick);
                uint256 newSqrtPriceX96 = uint256(currentSqrtPriceX96) * (100 - order.delta) / 100;
                int24 newStartingSellTick = TickMath.getTickAtSqrtRatio(uint160(newSqrtPriceX96));
                order.startingSellTick = newStartingSellTick;
            } else {
                // Selling NFTs (zeroForOne = false)
                // Transfer the NFT from the sender (seller) to the maker (buyer)
                IERC721(collection).safeTransferFrom(address(this), bidOrder.maker, bidOrder.bidId);

                // Update the startingBuyTick on the bonding curve
                uint160 currentSqrtPriceX96 = TickMath.getSqrtRatioAtTick(order.startingBuyTick);
                uint256 newSqrtPriceX96 = uint256(currentSqrtPriceX96) * (100 + order.delta) / 100;
                int24 newStartingBuyTick = TickMath.getTickAtSqrtRatio(uint160(newSqrtPriceX96));
                order.startingBuyTick = newStartingBuyTick;

                // Update the ethBalance of the order
                console.log("UNDERFLOW HERE");
                console.log("ORDER ETH BALANCE", order.ethBalance);
                console.log("BID ORDER", bidOrder.ethValue);
                console.log("ORDER ID", orderId);
                order.ethBalance -= (bidOrder.ethValue / 10e18);
            }



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

    //this is wrong, need to change process
    //figure out the price of 1 wei in that pool at
    function isThereEnoughEth(int24 tick, uint256 delta, uint256 numberOfNFTs, uint256 weiAmount) public returns (bool sufficient) {
        require(weiAmount > 0, "NO ETH");
        uint256 totalCost = 0;
        uint256 currentPrice = getEthPriceAtTick(tick);
        uint256 totalEth = (weiAmount * 10e18) * currentPrice;


        for (uint256 i = 0; i < numberOfNFTs; i++) {
            totalCost += currentPrice;
            // Adjust the price for the next NFT based on the delta percentage
            // Delta is expected to be provided as a percentage, e.g., 5 for 5%
            currentPrice = currentPrice * (100 - delta) / 100;
        }

        // Check if the total wei provided covers the total cost
        sufficient = totalEth >= totalCost;


        return sufficient;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }


}
