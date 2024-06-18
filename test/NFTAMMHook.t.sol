// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {NFTAMMHook} from "../src/NFTAMMHook.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import {PoolId} from "v4-core/types/PoolId.sol";

import {IERC721} from "openzeppelin/interfaces/IERC721.sol";

import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

contract NFTAMMHookTest is Test, Deployers {
    struct BidOrder {
        address maker;

        bool immediate;

        uint256 ethValue;

        uint256 bidId;

        int24 bidTick;

        uint256 orderId;
    }
    using CurrencyLibrary for Currency;

    MockERC20 token;
    MockERC721 collection = new MockERC721("Wrapped NFT", "wNFT");

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    NFTAMMHook hook;

    address public maker = address(1);

    PoolId id;



    function setUp() public {
        deployFreshManagerAndRouters();

        uint256[] memory tokenIds = new uint256[](5);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        tokenIds[2] = 2;
        tokenIds[3] = 3;
        tokenIds[4] = 4;

        for(uint256 i = 0; i < tokenIds.length; i++) {
            vm.prank(maker);
            collection.safeMint(address(maker), tokenIds[i]);
        }

        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            0,
            type(NFTAMMHook).creationCode,
            abi.encode(manager, "Wrapped Token", "TEST_WRAPPED", type(uint256).max, address(collection), 18)
        );

        // Deploy our hook
        hook = new NFTAMMHook{salt: salt}(
            manager,
            "Wrapped Token",
            "TEST_WRAPPED",
            type(uint256).max,
            address(collection),
            18
        );

        vm.deal(address(hook), 10000000000000000000000000000000000000000000);


        vm.prank(address(hook));
        hook.approve(address(swapRouter), type(uint256).max);
        vm.prank(address(hook));
        hook.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(address(hook));
        hook.approve(address(manager), type(uint256).max);
        vm.prank(address(hook));
        hook.approve(address(hook), type(uint256).max);



        tokenCurrency = Currency.wrap(address(hook));

        (key, id) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_RATIO_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );

    }



    function testMarketOrderCreation() public {
        int24 startingBuyTick = -60;
        int24 startingSellTick = 60;
        uint256 delta = 10;
        uint256 fee = 20;
        uint256 maxNumOfNFTsToBuy = 5;

        uint256 balanceBefore = collection.balanceOf(address(maker));

        //redundant tokenIds
        uint256[] memory tokenIds = new uint256[](5);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        tokenIds[2] = 2;
        tokenIds[3] = 3;
        tokenIds[4] = 4;

        vm.deal(maker, 10e18);

        vm.prank(maker);
        collection.setApprovalForAll(address(hook), true);
        vm.prank(maker);
        hook.marketMake{ value: 5}(
            address(collection),
            startingBuyTick,
            startingSellTick,
            tokenIds,
            delta,
            fee,
            maxNumOfNFTsToBuy
        );

       assert(hook.makerBalances(maker) > 0);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(startingBuyTick);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(startingSellTick);

        uint256 amount0 = 5; // eth deposited from market making order
        uint256 amount1 = hook.makerBalances(maker); // amount of wrapped tokens for NFT measured in eth. calculated in market maker order

        uint160 currentSqrtPrice;
        int24 currentTick;
        uint24 swapFee;
        (currentSqrtPrice, currentTick, fee, swapFee) = manager.getSlot0(id);

        uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
            currentSqrtPrice,
            sqrtRatioAX96,       // Lower tick sqrt price
            sqrtRatioBX96,       // Upper tick sqrt price
            amount0,             // ETH amount
            amount1              // wNFT amount (in ETH equivalent)
        );

        vm.deal(address(this), 2000000000);

        vm.prank(address(hook));

        uint256 liquidityToAddUint256 = uint256(liquidityToAdd);
        int256 liquidityToAddInt256 = int256(liquidityToAddUint256);

        modifyLiquidityRouter.modifyLiquidity{value: liquidityToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: liquidityToAddInt256
            }),
            "" // empty bytes
        );

    assert(balanceBefore - tokenIds.length == collection.balanceOf(address(maker)));
    }

   function testNFTPurchase() public {
        address trader = address(0x2);
       vm.deal(maker, 20);
       vm.deal(trader, 10 ether);
        uint256 initialTraderBalance = trader.balance;
        uint256 initialMakerBalance = maker.balance;


       //adding liquidity
        uint256 nftId = 0;
        uint256 fee = 20;
       uint160 currentSqrtPrice;
       int24 currentTick;
       uint24 swapFee;
       (currentSqrtPrice, currentTick, fee, swapFee) = manager.getSlot0(id);
       uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(0);
       uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(6);

       uint256 amount0 = 5 ether; // eth deposited from market making order
       uint256 amount1 = hook.makerBalances(maker) * 10e18; // amount of wrapped tokens for NFT measured in eth. calculated in market maker order


   uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
           currentSqrtPrice,
           sqrtRatioAX96,       // Lower tick sqrt price
           sqrtRatioBX96,       // Upper tick sqrt price
           amount0,             // ETH amount
           amount1              // wNFT amount (in ETH equivalent)
       );


        vm.deal(address(hook), 1000000000000000000000000000000000000000 ether);
       vm.prank(address(hook));

       uint256 liquidityToAddUint256 = uint256(liquidityToAdd);
       int256 liquidityToAddInt256 = int256(liquidityToAddUint256);

       modifyLiquidityRouter.modifyLiquidity{value: liquidityToAdd}(
           key,
           IPoolManager.ModifyLiquidityParams({
               tickLower: TickMath.minUsableTick(60),
               tickUpper: TickMath.maxUsableTick(60),
               liquidityDelta: liquidityToAddInt256
           }),
           "" // empty bytes
       );

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -2 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            withdrawTokens: true,
            settleUsingTransfer: true,
            currencyAlreadySent: false
        });

       uint256[] memory tokenIds = new uint256[](1);
       tokenIds[0] = nftId;



       vm.prank(maker);
       collection.setApprovalForAll(address(hook), true);
       vm.prank(maker);
       hook.marketMake{value: 5 ether}(address(collection), 0, 60, tokenIds, 10, 20, 1);



       vm.prank(address(trader));
        bytes memory order = hook.createBuyBidOrder{value: 2 ether}(1, nftId, maker);

        vm.prank(address(hook));
        swapRouter.swap{value: 2 ether}(key, params, testSettings, order);

        // Assertions for buying the NFT
        assertEq(collection.ownerOf(nftId), trader, "NFT should be transferred to the trader");
        assertGt(maker.balance, initialMakerBalance, "Maker should receive the Ether payment");
        assertLt(trader.balance, initialTraderBalance, "Trader's balance should be decreased by the Ether amount");
    }

    function testNFTSale() public {
        address trader = address(0x2);
        vm.deal(maker, 20);
        vm.deal(trader, 10 ether);
        uint256 initialTraderBalance = trader.balance;
        uint256 initialMakerBalance = maker.balance;
        uint256 nftId = 0;


        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            withdrawTokens: false,
            settleUsingTransfer: false,
            currencyAlreadySent: false
        });

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = nftId;
        tokenIds[1] = 1;

        vm.prank(maker);
        collection.setApprovalForAll(address(hook), true);
        vm.prank(maker);
        hook.marketMake{value: 5}(address(collection), 0, 60, tokenIds, 10, 20, 1);

        vm.prank(trader);
        collection.safeMint(address(trader), 6);

        vm.prank(trader);
        collection.setApprovalForAll(address(hook), true);

        vm.prank(trader);
        bytes memory order = hook.createSellOrder(1, 6, maker);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1006017734268818165,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
        });

        vm.prank(address(hook));
        swapRouter.swap(key, params, testSettings, order);

        // Assertions for selling the NFT
        assertEq(collection.ownerOf(nftId), maker, "NFT should be transferred to the maker");
        assertGt(trader.balance, initialTraderBalance, "Trader should receive the Ether payment");
        assertLt(maker.balance, initialMakerBalance, "Maker's Ether balance should be decreased by the Ether amount");
    }


}
