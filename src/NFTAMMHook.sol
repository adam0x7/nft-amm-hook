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

import {IERC721} from "openzeppelin-contracts/interfaces/IERC721.sol"

contract NFTAMMHook is ERC20, BaseHook {

    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address wrappedToken;
    address collection;

    uint256 private constant ONE = 1e18;  // 1e18 to represent 1.0 with 18 decimal precision
    uint256 private constant BASE = 100000;  // Base for 1.0001 represented as 1.0001 * 10^5 for precision
    uint256 private constant ONE_HUNDRED = 100;  // For percentage calculations


    struct MMOrder {
        mapping(uint256 => uint256) tokenIdsToTicks; //nfts being sold
        int24 startingBuyTick;
        int24 startingSellTick;
        int24 currentTick;
        uint256 ethBalance;
        uint256 maxNumOfNFTs;
        uint256 delta;
        uint256 fee;
        address nftAddress;
    }

    mapping(address => mapping(uint256 id => MMOrder)) public makersToOrders;
    uint256 public orderCount;


    constructor(IPoolManager _manager,
                    string memory _uri) BaseHook(_manager) ERC20() {
        orderCount = 0;
}

    function uri(uint256 id) public view virtual override returns (string memory) {
        return "url/id"; // fix this lol
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

    // @notice creating the market making order. A bid on the collection to both buy and sell nfts
    // @param _nftAddress - token address of the nft
    // @param - ids of the nfts being sold
    // @param - delta, the percent by which every order will change on the bond curve
    // @param - fee, the spread at which the maker will charge on their trades to be profitable
    function marketMake(address _nftAddress,
                            int24 startingBuyTick,
                            int24 startingSellTick,
                            uint256[] tokenIds,
                            uint256 delta,
                            uint256 fee,
                            uint256 maxNumOfNFTs) external payable returns(MMOrder memory) {
        require(address(msg.sender) != address(0));

        //creating the order
        //buy side: deposit eth into contract. delta represents the decreasing tick intervals to go down
        //add a check so that the eth deposited into the contract is == the amount of eth required to fulfill the order
        //or return it
        uint256 startingWeiPrice = getEthPriceAtTick(startingBuyTick);
        require(isThereEnoughEth(startingWeiPrice, delta, msg.value * 1e18, tokenIds.length()));

        //idea is to buy low sell high. selling tick needs to be slightly higher than buy tick
        require(startingSellTick > startingBuyTick)

        uint256 orderId = orderCount + 1;

        //creating the order

        MMOrder memory newOrder;
        newOrder.tokenIdsToTicks = createTickMappings(tokenIds, startingSellTick, delta);
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
        // make allowance 0
        IERC721(newOrder.nftAddress).safeTransferFrom(msg.sender, address(this), bytes())

        //calculate wrapped token amount


        address(this).transfer(msg.sender, )
        IERC20.(wrappedToken).allowance() // add allowance of 0 to msg.sender

        IERC20.(wrappedToken).transferFrom() // tokens of hook to user for escrow
        return newOrder;
    }



    function beforeSwap(address sender,
                        PoolKey calldata,
                        IPoolManager.SwapParams calldata, bytes calldata) external virtual returns (bytes4) {
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


    function calculateWrappedTokens(uint256 startingWeiPrice, string[] tokeniDS) internal returns(uint256) {
        // Calculate the total value of the NFTs being sold at the starting price
        uint256 totalValueAtStartingPrice = startingWeiPrice * tokenIds.length;

        // Initialize variables
        uint256 currentPrice = startingWeiPrice;
        uint256 totalWrappedTokensMinted = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
        // Calculate the wrapped tokens to mint for the current NFT
        uint256 wrappedTokensForCurrentNFT = (currentPrice * totalWrappedTokenSupply) / totalValueAtStartingPrice;

        // Mint the wrapped tokens for the current NFT
        _mintWrappedTokens(msg.sender, wrappedTokensForCurrentNFT);

        // Update the total wrapped tokens minted
        totalWrappedTokensMinted += wrappedTokensForCurrentNFT;

        // Calculate the price for the next NFT on the bond curve
        currentPrice = currentPrice * (100 - delta) / 100;
        }
        return currentPrice
    }

    // does this even work?
    function createTickMappings(
                    uint256[] memory tokenIds,
                    uint256 startingSellTick,
                    uint256 delta ) internal pure returns (mapping(uint256 => uint256) storage ticksMap) {
        uint256 currentTick = startingSellTick;


        for (uint256 i = 0; i < tokenIds.length; i++) {
            ticksMap[tokenIds[i]] = currentTick;
            currentTick = currentTick * (100 - delta) / 100;
        }
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
                                uint256 numberOfNftS) public pure returns (uint256) {
            uint256 remainingEth = totalEth;
            uint256 currentPrice = initialPrice;
            uint256 coveredSteps = 0;

            for (uint256 i = 0; i < steps; i++) {
                if (remainingEth >= currentPrice) {
                    remainingEth -= currentPrice;
                    coveredSteps++;

            // Calculate next step's price
            currentPrice = currentPrice * (ONE_HUNDRED - delta) / ONE_HUNDRED;
            } else {
                    break;
                }
            }
            return remainingEth >= 0 ? true : false;
        }





}
