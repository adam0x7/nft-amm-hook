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
        //mapping for the token ids to whichever tick they are priced at. this is the sell side of the order
        mapping(uint256 => int24) tokenIdsToTicks;
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
    ) external payable {
        require(_nftAddress == collection);
        require(address(msg.sender) != address(0));

        //idea is to buy low sell high. selling tick needs to be slightly higher than buy tick
        require(startingSellTick > startingBuyTick);

        uint256 startingWeiPrice = getEthPriceAtTick(int256(startingBuyTick));
        //checking whether there is enough eth deposited to cover their order
        require(isThereEnoughEth(startingWeiPrice, delta, msg.value * 1e18, tokenIds.length));

        orderId++;

        //creating the order
        MMOrder storage newOrder;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            newOrder.tokenIdsToTicks[tokenIds[i]] = createTickMappingsForSingleToken(int24(startingSellTick), delta, i);
        }
        newOrder.startingBuyTick = startingBuyTick;
        newOrder.startingSellTick = startingSellTick;
        newOrder.currentTick = startingSellTick;
        newOrder.ethBalance = msg.value;
        newOrder.maxNumOfNFTs = maxNumOfNFTs;
        newOrder.delta = delta;
        newOrder.fee = fee;
        newOrder.nftAddress = _nftAddress;
        makersToOrders[msg.sender][orderId] = newOrder;

        //transfer nfts to hook from order
        //mint wrapped tokens to user according to wei price
        //TODO move this to its own function / library
        for (uint256 i = 0; i < tokenIds.length; i++) {
        IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        //updating wrapped token share. user doesn't actually get the tokens so the hook has to supply liquidity for them
        determineWrappedTokenShare(startingWeiPrice, tokenIds, delta);
    }

    function determineWrappedTokenShare(uint256 startingWeiPrice, uint256[] calldata tokenIds, uint256 delta) internal {
        // Calculating the total value of the NFTs being deposited in wei
        uint256 saleOrderInWei = totalDecreasingPrice(startingWeiPrice, delta, tokenIds.length);
        uint256 saleOrderInEth = saleOrderInWei / 1e18;
        //for purpose of testing, each wrapped nft token == 1 ether
        makerBalances[msg.sender] += saleOrderInEth;
    }

    function createTickMappingsForSingleToken(int24 startingSellTick, uint256 delta, uint256 index) internal pure returns (uint24) {
        uint24 currentTick = uint24(startingSellTick);
        for (uint256 i = 0; i < index; i++) {
            currentTick = uint24(uint256(currentTick) * (100 - delta) / 100);
        }
        return currentTick;
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
        return this.beforeSwap.selecter;
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


    function getEthPriceAtTick(int256 tick) public pure returns (uint256) {
            uint256 result = ONE;
            uint256 factor = BASE;

            if (tick < 0) {
                tick = -tick;  // Make tick positive for calculation
                factor = ONE * ONE / BASE;  // Use reciprocal for negative ticks
            }

            for (int256 i = 0; i < tick; i++) {
                result = result * factor / ONE;
            }

            return result;
        }

    function isThereEnoughEth(uint256 initialPrice,
                                uint256 delta,
                                uint256 totalEth,
                                uint256 numberOfNFTs) public pure returns (bool) {
            uint256 remainingEth = totalEth;
            uint256 currentPrice = initialPrice;
            uint256 coveredSteps = 0;

            for (uint256 i = 0; i < numberOfNFTs; i++) {
                if (remainingEth >= currentPrice) {
                    remainingEth -= currentPrice;
                    coveredSteps++;

            // Calculate next step's price on the bond curve
            currentPrice = currentPrice * (ONE_HUNDRED - delta) / ONE_HUNDRED;
            } else {
                    break;
                }
            }
            return remainingEth >= 0 ? true : false;
        }

}
