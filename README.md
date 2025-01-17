**To check the Blast version code, please switch to the [Blast branch](https://github.com/OutrunFinance/Outrun-AMM/tree/blast)**

# 💱 OutSwap

## Outrun AMM

**Outrun AMM** is built on classic AMM and includes several innovative improvements. The main features are as follows:

* **Capture Native Yield ([Blast L2](https://docs.blast.io/about-blast) Only)**: On Blast L2, the Outrun AMM adds extra logic to handle the native yield generated by WETH and USDB. All native yield will be distributed to liquidity providers based on their LP shares, ensuring fair allocation and increasing the profitability for market makers. The yield is issued in the form of [SY(Standardized Yield)](https://outrun.gitbook.io/doc/outstake/yield-tokenization/sy).
* **Separation of Liquidity and Market-Making Fees**: Outrun AMM improves the management of market-making fees by separating liquidity from fee collection. This allows users to collect fees without removing liquidity, providing greater flexibility and convenience for liquidity providers.
* **New Fee Tiers**: All **classic AMM** pools have a fixed swap fee of **0.3%**, which results in a lack of flexibility for LPs (liquidity providers) who cannot seek different fee structures based on the assets they provide to the exchange. Outrun AMM will introduce new fee tiers for pool creators, allowing them to build different trading pools for various types of assets when launching pools on Outrun AMM.
* **Referral Commission Engine**: Outrun AMM is currently the only automated market maker on the market integrated with a referral commission engine. We have redesigned the underlying code and opened the referral commission engine to everyone, thereby increasing the composability of the protocol. The rewards for the referral bonus come from the protocol fees and do not harm the interests of LPs. At the same time, this attracts more transactions, bringing higher income to LPs.

For more details, please refer to the product documentation : [Outrun Official Doc](https://outrun.gitbook.io/doc "Outrun Official Doc")