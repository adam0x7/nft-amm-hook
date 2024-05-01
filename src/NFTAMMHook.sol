// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract NFTAMMHook is ERC1155, BaseHook {

    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;


    struct MMOrder {
        uint256 id;
        string[] uris;
        int24 tick;
    }

    mapping(address => mapping(uint256 id => MMOrder)) public makersToOrders;
    uint256 public orderCount;


    constructor(IPoolManager _manager,
                    string memory _uri) BaseHook(_manager) ERC1155() {
        orderCount = 0;
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


    function createMMOrder(string[] calldata uris, int24 tick) public returns(MMOrder memory) {
        require(address(msg.sender) != address(0));
        uint256 orderId = orderCount + 1;
        MMOrder memory newOrder = MMOrder(orderId, uris, tick);
        makersToOrders[msg.sender][orderId] = newOrder;
        return newOrder;
    }





}
