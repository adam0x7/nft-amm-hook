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


import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

contract NFTAMMHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 token;
    MockERC721 collection = new MockERC721("Wrapped NFT", "wNFT");

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    NFTAMMHook hook;

    address maker = address(1);

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
            abi.encode(manager, "Wrapped Token", "TEST_WRAPPED", 100000000, address(collection), 18)
        );

        // Deploy our hook
        hook = new NFTAMMHook{salt: salt}(
            manager,
            "Wrapped Token",
            "TEST_WRAPPED",
            100000000,
            address(collection),
            18
        );

        vm.deal(address(hook), 10000000000000000000000000000000000000000000);

        hook.approve(address(swapRouter), type(uint256).max);
        hook.approve(address(modifyLiquidityRouter), type(uint256).max);

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

    function testTransferFromHookToManager() public {
        // Check initial balance
        uint256 initialBalance = hook.balanceOf(address(hook));
        console.log("Initial Balance of hook: ", initialBalance);

        // Check if the balance is sufficient
        require(initialBalance >= 5, "Insufficient balance for transfer");

        vm.prank(address(hook));
        hook.approve(address(manager), 10);

        // Check allowance (if applicable)
        uint256 allowance = hook.allowance(address(hook), address(manager));
        console.log("Allowance from hook to manager: ", allowance);

        // Perform the prank and the transfer
        vm.prank(address(hook));
        bool success = hook.transferFrom(address(hook), address(manager), 5);
        require(success, "Transfer failed");

        // Check final balance
        uint256 finalBalance = hook.balanceOf(address(hook));
        console.log("Final Balance of hook: ", finalBalance);

        // Ensure the transfer happened correctly
        assert(finalBalance == initialBalance - 5);
    }


//    function testMarketOrderCreation() public {
//        int24 startingBuyTick = -60;
//        int24 startingSellTick = 60;
//        uint256 delta = 10;
//        uint256 fee = 20;
//        uint256 maxNumOfNFTsToBuy = 5;
//
//        uint256 balanceBefore = collection.balanceOf(address(maker));
//
//        //redundant tokenIds
//        uint256[] memory tokenIds = new uint256[](5);
//        tokenIds[0] = 0;
//        tokenIds[1] = 1;
//        tokenIds[2] = 2;
//        tokenIds[3] = 3;
//        tokenIds[4] = 4;
//
//        vm.deal(maker, 10e18);
//
//        vm.prank(maker);
//        collection.setApprovalForAll(address(hook), true);
//        vm.prank(maker);
//        hook.marketMake{ value: 5}(
//            address(collection),
//            startingBuyTick,
//            startingSellTick,
//            tokenIds,
//            delta,
//            fee,
//            maxNumOfNFTsToBuy
//        );
//
//       assert(hook.makerBalances(maker) > 0);
//
//        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(startingBuyTick);
//        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(startingSellTick);
//
//        uint256 amount0 = 5; // eth deposited from market making order
//        uint256 amount1 = hook.makerBalances(maker); // amount of wrapped tokens for NFT measured in eth. calculated in market maker order
//
//        uint160 currentSqrtPrice;
//        int24 currentTick;
//        uint24 swapFee;
//        (currentSqrtPrice, currentTick, fee, swapFee) = manager.getSlot0(id);
//
//        uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
//            currentSqrtPrice,
//            sqrtRatioAX96,       // Lower tick sqrt price
//            sqrtRatioBX96,       // Upper tick sqrt price
//            amount0,             // ETH amount
//            amount1              // wNFT amount (in ETH equivalent)
//        );
//
//        vm.deal(address(this), 2000000000);
//
//        vm.prank(address(hook));
//
//        uint256 liquidityToAddUint256 = uint256(liquidityToAdd);
//        int256 liquidityToAddInt256 = int256(liquidityToAddUint256);
//
//        modifyLiquidityRouter.modifyLiquidity{value: liquidityToAdd}(
//            key,
//            IPoolManager.ModifyLiquidityParams({
//                tickLower: -60,
//                tickUpper: 60,
//                liquidityDelta: liquidityToAddInt256
//            }),
//            "" // empty bytes
//        );
//
//    assert(balanceBefore - tokenIds.length == collection.balanceOf(address(maker)));
//    }

}



