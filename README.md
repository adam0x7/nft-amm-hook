
# Creating An NFT AMM As A Uniswap Hook 🦄🖼️
<blockquote style="border-left: 4px solid #f0ad4e; background-color: #fcf8e3; padding: 10px; margin: 20px 0; color: #8a6d3b;">
<strong>Notice:</strong> This is an important message! Click here to read the full article: [Mirror Article](https://mirror.xyz/0x0e729b11661B3f1C1E829AAdF764D5C3295e1256/u1JYJ6_XWf-bgyQIZjHYsC22WgArKCRJxk8pf37am3Y)
</blockquote>

To include your shell commands in a code snippet in a Markdown document, you can group them together into a single code block, labeling each command with a comment for clarity. Here's how you could format it:

```markdown
# Install dependencies using Forge
forge install

# Build the project specifying the EVM version and IR generation
forge build --evm-version cancun --via-ir
```


This structure uses comments within the shell script code block to explain what each command does, keeping it neat and easy to understand. When displayed in a Markdown renderer, this will show up as a single code block with two distinct commands, each preceded by a comment explaining its purpose.

## Overview 🌐
The `NFTAMMHook` is a Uniswap V4 Hook that is a POC for creating an NFT AMM using the `afterSwap` hook.
## Key Features 🌟

- **Market Making for NFTs** 📈: Users can create orders to buy and sell NFTs at specified price points, adjusting the prices dynamically based on a predefined delta. These market makers create immediate liquidity for the NFT on the buy and sell sides of the NFT collection.
- **Bonding Curve Pricing** 📊: Implements a bonding curve for price determination, where the price adjusts according to a set delta percentage as more NFTs are bought or sold. This allows market makers to `buy low / sell high`
- **Integration with Uniswap V4 Hooks** 🔗: Utilizes the after swap hooks to transfer our NFT, influenced by whether or not we are making a zeroForOne trade.  
- **Wrapped NFTs (wNFTs)** 🎁: Supports the concept of wrapped NFTs, where NFTs are wrapped into a fungible token format to facilitate easier trading and liquidity provision.
