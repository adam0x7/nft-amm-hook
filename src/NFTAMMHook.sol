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
    constructor(){

    }
}
