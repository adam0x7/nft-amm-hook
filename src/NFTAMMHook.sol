pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IERC721} from "openzeppelin/interfaces/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {PriceLib} from "./utils/PriceLib.sol";

contract NFTAMMHook is ERC20, BaseHook, IERC721Receiver {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using PriceLib for int24;
    using PriceLib for uint256;

    address public immutable collection;

    struct MMOrder {
        int24 startingSellTick;
        int24 startingBuyTick;
        int24 currentTick;
        uint256 ethBalance;
        uint256 maxNumOfNFTs;
        uint256 delta;
        uint256 fee;
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
    mapping(address => mapping(uint256 => MMOrder)) public makersToOrders;
    mapping(address => uint256) public makerBalances;
    uint256 public orderId;
    mapping(uint256 => address) public bidsToBuyers;

    /**
     * @dev Constructor function.
     * @param _manager The address of the pool manager.
     * @param name The name of the ERC20 token.
     * @param symbol The symbol of the ERC20 token.
     * @param initialSupply The initial supply of the ERC20 token.
     * @param _collection The address of the NFT collection.
     * @param decimals The number of decimals for the ERC20 token.
     */
    constructor(
        IPoolManager _manager,
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _collection,
        uint8 decimals
    ) BaseHook(_manager) ERC20(name, symbol, decimals) {
        orderId = 0;
        collection = _collection;
        _mint(address(this), initialSupply);
    }

    /**
     * @dev Returns the hook permissions.
     * @return The hook permissions.
     */
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

    /**
     * @dev Creates a market-making order.
     * @param _nftAddress The address of the NFT collection.
     * @param startingBuyTick The starting tick for buying NFTs.
     * @param startingSellTick The starting tick for selling NFTs.
     * @param tokenIds The token IDs of the NFTs being sold.
     * @param delta The percentage change for each order on the bonding curve.
     * @param fee The swap fee for buying or selling into the order.
     * @param maxNumOfNFTs The maximum number of NFTs the order is willing to purchase.
     */
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
        require(startingSellTick > startingBuyTick, "sell tick is less than or equal to buy tick");
        require(PriceLib.isThereEnoughEth(startingSellTick, delta, maxNumOfNFTs, msg.value), "there is not enough eth");

        orderId++;
        MMOrder storage order = makersToOrders[msg.sender][orderId];

        for (uint256 i = 0; i < tokenIds.length; i++) {
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

        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        determineWrappedTokenShare(TickMath.getSqrtRatioAtTick(startingSellTick), tokenIds, delta);
    }

    /**
     * @dev Creates a buy bid order.
     * @param _orderId The ID of the market-making order.
     * @param nftId The ID of the NFT being bought.
     * @param _maker The address of the market maker.
     * @return The encoded bid order data.
     */
    function createBuyBidOrder(uint256 _orderId, uint256 nftId, address _maker) external payable returns (bytes memory) {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        MMOrder storage order = makersToOrders[_maker][orderId];
        require(msg.value >= PriceLib.getEthPriceAtTick(order.currentTick), "Not tick equivalent or greater");

        BidOrder memory bidOrder = BidOrder(_maker, true, msg.value, nftId, order.currentTick, _orderId);
        bidsToBuyers[bidOrder.bidId] = msg.sender;
        return abi.encode(bidOrder);
    }

    /**
     * @dev Creates a sell order.
     * @param _orderId The ID of the market-making order.
     * @param nftId The ID of the NFT being sold.
     * @param _maker The address of the market maker.
     * @return The encoded sell order data.
     */
    function createSellOrder(uint256 _orderId, uint256 nftId, address _maker) external returns (bytes memory) {
        MMOrder storage order = makersToOrders[_maker][_orderId];
        int24 currentTick = order.currentTick;

        IERC721(collection).safeTransferFrom(msg.sender, address(this), nftId);

        BidOrder memory sellOrder = BidOrder(_maker, true, PriceLib.getEthPriceAtTick(currentTick), nftId, currentTick, _orderId);
        bidsToBuyers[sellOrder.bidId] = msg.sender;
        return abi.encode(sellOrder);
    }

    /**
     * @dev Fallback function to receive Ether.
     */
    fallback() external payable {}

    /**
     * @dev Determines the wrapped token share for the deposited NFTs.
     * @param sqrtPriceX96 The square root price ratio.
     * @param tokenIds The token IDs of the deposited NFTs.
     * @param delta The percentage change for each order on the bonding curve.
     */
    function determineWrappedTokenShare(uint160 sqrtPriceX96, uint256[] calldata tokenIds, uint256 delta) internal {
        uint256 priceRatio = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 96;

        uint256 totalValueInToken0 = 0;
        uint256 currentPriceInToken0 = priceRatio;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalValueInToken0 += currentPriceInToken0;
            currentPriceInToken0 = currentPriceInToken0 * (100 - delta) / 100;
        }

        uint256 totalValueInEther = totalValueInToken0 / 1e18;
        makerBalances[msg.sender] += totalValueInEther;
    }

    /**
     * @dev Creates the square root price for a single token based on the tick and delta.
     * @param tick The starting tick.
     * @param delta The percentage change for each order on the bonding curve.
     * @param index The index of the token.
     * @return The square root price ratio for the token.
     */
    function createSqrtPriceForSingleToken(int24 tick, uint256 delta, uint256 index) internal view returns (uint160) {
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "Tick is out of range");

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        for (uint256 i = 0; i < index; i++) {
            uint256 reducedPrice = uint256(sqrtPriceX96) * (100 - delta) / 100;
            sqrtPriceX96 = uint160(reducedPrice);
        }

        return sqrtPriceX96;
    }

    /**
     * @dev Hook function called before a swap.
     * @param sender The address of the sender.
     * @param key The pool key.
     * @param params The swap parameters.
     * @param hookData The hook data.
     * @return The selector of the beforeSwap function.
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        return this.beforeSwap.selector;
    }

    /**
     * @dev Hook function called after a swap.
     * @param sender The address of the sender.
     * @param key The pool key.
     * @param params The swap parameters.
     * @param balanceDelta The balance delta.
     * @param hookData The hook data.
     * @return The selector of the afterSwap function.
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta balanceDelta,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4) {
        BidOrder memory bidOrder = abi.decode(hookData, (BidOrder));
        MMOrder storage order = makersToOrders[bidOrder.maker][bidOrder.orderId];

        if (params.zeroForOne) {
            IERC721(collection).safeTransferFrom(address(this), bidsToBuyers[bidOrder.bidId], bidOrder.bidId);
            (bool success, ) = bidOrder.maker.call{value: bidOrder.ethValue}("");
            require(success, "Transfer failed");

            uint160 currentSqrtPriceX96 = TickMath.getSqrtRatioAtTick(order.startingSellTick);
            uint256 newSqrtPriceX96 = uint256(currentSqrtPriceX96) * (100 - order.delta) / 100;
            int24 newStartingSellTick = TickMath.getTickAtSqrtRatio(uint160(newSqrtPriceX96));
            order.startingSellTick = newStartingSellTick;
        } else {
            IERC721(collection).safeTransferFrom(address(this), bidOrder.maker, bidOrder.bidId);

            uint160 currentSqrtPriceX96 = TickMath.getSqrtRatioAtTick(order.startingBuyTick);
            uint256 newSqrtPriceX96 = uint256(currentSqrtPriceX96) * (100 + order.delta) / 100;
            int24 newStartingBuyTick = TickMath.getTickAtSqrtRatio(uint160(newSqrtPriceX96));
            order.startingBuyTick = newStartingBuyTick;

            order.ethBalance -= bidOrder.ethValue;
        }

        return this.afterSwap.selector;
    }

    /**
     * @dev Hook function called when receiving an ERC721 token.
     * @param operator The address of the operator.
     * @param from The address of the previous owner.
     * @param tokenId The token ID of the received NFT.
     * @param data Additional data with no specified format.
     * @return The selector of the onERC721Received function.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}