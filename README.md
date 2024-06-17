# NFTAMMHook.sol 📜

## Overview 🌐
`NFTAMMHook` is a smart contract designed to integrate with Uniswap V4's hook system, allowing for the creation of market making orders for NFTs within a liquidity pool environment. This contract leverages the flexibility of Uniswap V4 hooks to facilitate both buying and selling NFTs based on a bonding curve mechanism.

## Key Features 🌟

- **Market Making for NFTs** 📈: Users can create orders to buy and sell NFTs at specified price points, adjusting the prices dynamically based on a predefined delta.
- **Bonding Curve Pricing** 📊: Implements a bonding curve for price determination, where the price adjusts according to a set delta percentage as more NFTs are bought or sold.
- **Integration with Uniswap V4 Hooks** 🔗: Utilizes the before and after swap hooks to integrate custom logic into the trading process, enhancing the flexibility and functionality of NFT trades.
- **Wrapped NFTs (wNFTs)** 🎁: Supports the concept of wrapped NFTs, where NFTs are wrapped into a fungible token format to facilitate easier trading and liquidity provision.

## Functions 🛠️

### Market Making
- `marketMake` 📉: Allows a user to create a market making order by specifying parameters such as the NFT collection address, buy and sell ticks, and the maximum number of NFTs they are willing to trade. This function also handles the transfer of NFTs to the contract and the initial setup of the order.

### Order Management 🗂️
- `createBuyBidOrder` 🛒: Facilitates the creation of a buy order for NFTs at the current market price.
- `createSellOrder` 💰: Allows users to sell their NFTs at the current market price, transferring the NFT to the contract and setting up the sale.

### Price Calculation 🧮
- `getEthPriceAtTick` 💵: Calculates the ETH price at a given tick using the Uniswap V4 TickMath library.
- `createSqrtPriceForSingleToken` 🔢: Determines the square root price for a single token based on its position in the order and the specified delta.

### Liquidity Management 💧
- `determineWrappedTokenShare` 📦: Calculates the share of wrapped tokens corresponding to the NFTs deposited, based on the current price and the bonding curve.

### Swap Hooks 🪝
- `afterSwap` 🔄: Handles the transfer of NFTs and ETH post-swap, adjusting the bonding curve and updating balances accordingly.
