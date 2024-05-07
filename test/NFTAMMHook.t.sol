// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {Test} from "forge-std/Test.sol";

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

contract PointsHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;


    MockERC20 token;
    MockERC721 collection;

    Currency ethCurrency = Currency.wrap(0);
    Currency tokenCurrency;

    NFTAMMHook hook;


    function setUp() public {
        deployFreshManagerAndRouters();

        token = new MockERC20();
        tokenCurrency = Currency.wrap(address(token));


        token.mint(address(1), 1000 ether);

        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            0,
            type(NFTAMMHook).creationCode,
            abi.encode(manager, "Wrapped Token", "TEST_WRAPPED", 18)
        );

        // Deploy our hook
        hook = new NFTAMMHook{salt: salt}(
            manager,
            "Wrapped Token",
            "TEST_WRAPPED",
            18
        );

        token.mint(address(hook), 1000 ether);
        vm.deal(address(hook, 1000));

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        (key, ) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_RATIO_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );
    }

//    function testMarketOrderCreation() public {
//            //need to assert that user has less eth, and has deposited that eth
//            //need to assert that the user has transferred the nft
//            //need to assert that the user has minted wnft
//        int24 startingBuyTick = -1;
//        int24 startingSellTick = 1;
//
//
//
//        hook.marketMake(
//            address(collection),
//            startingBuyTick,
//            startingSellTick,
//
//        );
//
//
//
//    }

}
