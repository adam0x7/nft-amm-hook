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

contract NFTAMMHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 token;
    MockERC721 collection = new MockERC721("Wrapped NFT", "wNFT");

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    NFTAMMHook hook;

    address maker = address(1);


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

        vm.deal(address(hook), 1000);

        hook.approve(address(swapRouter), type(uint256).max);
        hook.approve(address(modifyLiquidityRouter), type(uint256).max);

        tokenCurrency = Currency.wrap(address(hook));

        (key, ) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_RATIO_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );
    }

    function testMarketOrderCreation() public {
        int24 startingBuyTick = -1;
        int24 startingSellTick = 1;
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
    // user calls this function with the parameters, as well as the eth value for the amount they're going to deposit
        vm.deal(maker, 10);

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
//        console.log(hook.makersToOrders);

        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether
            }),
            "" // empty bytes
        );

    assert(balanceBefore - tokenIds.length == collection.balanceOf(address(maker)));
    }

}
