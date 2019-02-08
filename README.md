# Collateral Manager  
Collateral on the blockchain incurs massive opportunity costs by requiring capital that could be put to productive use elsewhere to be held in smart contracts until settlement. Lost capital held as on-chain collateral is a very real and rapidly growing challenge that drastically decreases liquidity across the network, disincentivizes staking funds in any smart contract, and cripples the growth potential of the blockchain economy as a whole.  
  
This smart contract system leverages price feeds, external keepers, and decentralized exchanges to allow users more control over their collateral. The collateral-requiring smart contract (referrred to as the admin contract) can implement any arbitrary logic, with the difference being that the funds serving as collateral are held in the Collateral Manager smart contract system rather than the admin contracct itself. The admin contract still has control of all logic regarding how and when these funds are payed out. Users can overcollateralize their positions according to risk parameters set by the admin contract, then submit an order from a decentralized exchange and BAM! They can hold their collateral in any asset that they choose and trade it as they please, provided the total value of the assets locked in the contract stays above the minimum required collateralization ratio (as set by the admin contract).  
  
I believe that the ability to more freely manage collateral on the blockchain has huge implications for the viability of on-chain secured debt, payment channels, and decentralized finance as a whole.

### Why is collateral on the blockchain unique?
In everyday life, at least in most developed countries, collateral is able to live a "double life" by serving to secure debt or other guarantees while also being utilized for the property's originally intended purpose; i.e. a mortgage, which allows you to live in your house while it serves as collateral for your loan and as a (hopefully appreciating) asset. The downside to this is high counterparty risk in off-chain transactions. While smart contracts on the blockchain provide a greatly improved way to manage counterparty risk, they require full collateralization. This creates a unique problem, because capital that is locked away in smart contracts is lost liquidity. As the adoption of smart contracts increases, this problem will only get bigger. Additionally, losing access to your capital by relinquishing it to a smart contract is a tremendous disincentive for users, especially if the quote currency of the smart contract in question does not align with their ideal risk profile. If I want the safest possible investment I can find, but the only way to enter a smart contract is to leave it in an extremely volatile asset for the duration of the agreement, I am much less likely to do so. Alternatively, I might want to maximize my risk exposure and consider any collateral that must be held in a low-yield asset to be lost opportunity.  
  
This leveraging of personal property to serve a "double life" as collateral is arguably the single most important ingredient in the growth of a successful economy, an idea that is explored in Hernando de Soto's book, The Mystery of Capital. Off chain, the challenge is often finding a way to fix an asset's economic potential so that it can also serve as collateral. On the blockchain, the challenge is finding a way to allow collateral to also serve as an asset.  

## How does it work?
There are a few different players and components involved in the system in ways that are very similar to other blockchain projects, but may require some introduction if you haven't come across them before. While there are quite a few smart contracts within the Collateral Manager system itself, we will assume the system to be one monolithic entity for the time being. The Contract Collateral Manager system as a whole is also referred to as CCM, for the sanity of all involved. A lot of inspiration for the design was taken from both the Multi-Collateral Dai system and the dYdX Protocol, so if you are familiar with either of these systems you will recognize many similar elements (and a big thanks to both of these great projects!).  

### Participants  

- **Admins** -> The *holders* of collateral. Admins are assumed to be (but aren't necessarily) smart contracts that the *users* presumably already have some purpose to interact with. Admin contracts can hold and distribute collateral by any arbitrary logic.  
- **Users**  -> Users are the *owners* of collateral. However, they are not in full control of this collateral. The collateral must remain in the Collateral Manager system above the minimum required amount in perpetuity *unless* the admin contract moves it or absolves the user of the obligation (closing the account).  
- **Oracles** -> Oracles, or price feeds, are sources of external information on the blockchain. Specifically, the oracles in the Collateral Manager system provide the current market exchange rate between token pairs.
- **Keepers** -> Keepers are external actors that are incentivized in some way to maintain the proper function of the system as a whole. *Admin* contracts can set the risk parameters for assets that their users can hold, and they can also set the rewards for keepers. Keepers watch the value of collateral held in the contract, waiting for the price of the held asset (`heldGem`) to fall relative to the quote asset (`owedGem`). As soon as it does, a keeper can `bite` the account, triggering a liquidation of collateral and earning a reward. In some cases, *admin* contracts may set this reward to zero if there is some mechanism already in place for rewarding keepers that trigger liquidations of collateral held by the contract.  
- **DEX's and trading counterparties** -> *Users* can submit orders that offer to buy their currently held assets from any decentralized exchange (DEX) with an on-chain settlement layer. Currently, the Collateral Manager system can only be a taker on exchanges, but in the future users may be able to place orders of their own on DEX's.  
  
### Basic System Flow  
1. The *user* sends some transaction to the *admin* contract that requires depositing of collateral.  
  
2. The *admin* contract performs any necessary logic, then opens an account in the Collateral Manager system. Just like requiring the transfer of an ERC20 token to it's own address to complete it's logic, the admin contract can require the successful opening of an account (which includes the transferring of the ERC20 from the user to the CCM contracts).  
  
**What does this "account" look like?**  
The account is made up of the address of the admin contract, which has ultimate control over the funds, the address of the user, the tokens and the account's balance in each token, and a few other details necessary for steps further along in the process. The **quote token**, or `owedGem`, is the only token that the admin contract ever deals with. The amount of collateral that must be held in the account is always denominated in this token. If the user holds another token in the account, price feeds are used to denominate the current value of the held assets in units of the quote token. The **held token** (`heldGem`), is any token that the user wishes to hold (and the admin has set risk parameters for) that is not the quote token. A user can keep a mix of both quote token and held token in the account, but the quote token is the 'ultimate source of truth' for the account.

3. The user, whose collateral is now held in the CCM contracts, now chooses to swap the currently held asset for a new one. For the sake of demonstration, we will say that the *admin* contract requires payout in WETH (wrapped Ether), making this the quote token. The user prefers less volatility, so she chooses to hold her collateral in DAI (a stablecoin). In order to make this change, she first has to overcollateralize her account.  
Because the value of a new held token could fluctuate relative to the value of the quote token, there is some minimum collateralization ratio (`biteLimit`) above which a user must be before they can hold a balance of the owed token below the owed amount. This ratio is set by the admin contract based on the risk parameters for each token pair. So, the user deposits a bit more WETH than required so that she can trade all of it for a new asset.  
The user then finds a 0x order from a relayer (note: only the 0x wrapper is currently implemented, but any DEX could be used). She submits this order to the CCM contracts, and the contracts execute the order. Now, she has no WETH in the account. All of her collateral is held in DAI.  

4. The price of DAI begins to fluctuate relative to WETH. If the price of WETH rises, the relative price of DAI falls. This means that the user might need to add more collateral to her account or trade the existing collateral back into WETH to avoid a liquidation. If liquidated, the user must pay a penalty. However, accounts can be set up with no penalty with the assumption that there could be another system in place to manage liquidations without incentivizing external keepers. For example, a service similar to Dharma Lever might include the cost of liquidations in the interest rate on the debt.  
The current mechanism for liquidations is extremely simple, requiring any keeper who `bites` an account to immediately purchase all of the collateral in the account that is not currently held in the quote token. To incentivize keepers to trigger these liquidations, the collateral is sold at a discount from the market price (as determined by the price feed). This allows the keeper to atomically sell that collateral on a DEX for a riskless profit. There are some downsides to this method of liquidation, and the future plan is to sell collateral at auction, similar to the auctions planned for the Multi-Colalteral Dai system.  
  

5. When the admin contract needs to pay out some of the collateral from the account, it can either lower the required collateral amount (if 'paying' to the user), or `call` the account with a certain balance that must be placed in the quote currency. The admin contract determines a `callTime` when the account is open, so the user is aware how much time they have to exchange assets. These calls (similar in concept to a margin call) can work in a few different ways:  
    - If the admin contract sets the `callTime` to 0, the account is eligible for liquidation immediately. As soon as it is liquidated, a second call from any address will trigger the due payment (still implementing this). In the future, an auction of the collateral could be triggered automatically and the call paid out. The assumption is that an account with a callTime of 0 has another method of 'warning' the user of an impending payment, but this is not necessarily the case. If, for example, the admin contract is a payment channel, I can avoid a call by know the value of the highest payment signature I have sent to my channel counterparty. Imagine I have a total collateral requirement of 1,0000 WETH, all held in DAI, and I have sent signatures for a total of 200 WETH to my counterparty so far. My counterparty can claim that 200 WETH at any time, so to avoid a liquidation I will make sure that I keep 200 WETH in the account, with the remainder held in my token of choice.  
    - If the `callTime` = x, with x > 0, the user has x amount of time to trade for the owed tokens necessary to cover the call, or face the same fate as above.  
    - If the called amount is already in the account in the quote token, it is payed out immediately (although, the system currently uses a 'pull' payment pattern, so it just gets added to the payees claim balance).  
  
## Other Elements  

- **Interest** -> As part of the risk parameters for a token pair, the admin contract can set an interest rate charged on the amount of owed quote token that is not held in the quote token itself. For example, take a user with required collateral of 1,000 WETH. The user holds 800 WETH in the account, with the remainder in DAI. No matter how much DAI the user holds in the account, the interest will only be charged on the 200 WETH deficit (1,000 WETH - 800 WETH). However, the interest rate that is charged is based on the unique risk parameters for the WETH/DAI trading pair, based on the fact that the risk associated with the deficit comes from the relative volatility of the asset that is held in place of it.  
  
- **Safe Orders** -> To mitigate the risk of incurring a liquidation penalty as a result of a call from the admin contract, users can set a "safe order". This can be any order, but the most likely case is that the user submits an order for which they, or a third-party service, are the taker of the order. In this case, the actual spot price provided by the order does not matter, only that the order offers to buy some amount of the collateral in the contract in exchange for some amount of quote token. In the event of an unanticipated call (account holds less quote token than the called amount), the safe order is taken on the designated exchange, and the proceeds are used to cover the call deficit.  
A valid question would be, if I have the money to cover the deficit, why not just put it in the account. There are a few situations where this is useful:  
- The user prefers to have more liquid access to the capital that she holds in the quote token, so she keeps it in her wallet and allows it to be drawn out by a *safe order* whenever necessary.  
- The user can predict the maximum called value based on the logic of the admin contract, in which case the safe order only needs to be for a portion of the total required collateral amount.  
- The user contracts with a third party service or smart contract and pays a regular premium in exchange for the third party providing a safe order to "bail out" the user in the event of an unexpected call.  
  
## Potential Applications  
I believe that there are countless blockchain protocols and applications that would benefit from the ability to hold collateral while also giving their users the ability to use that collateral to hold other blockchain assets. In a sense, this base protocol can provide a sort of blockchain bank. But it's a sharp contrast to the bank holding your money and paying a miniscule interest rate in exchange for the opportunity to loan that money out. Instead, you can pay a small interest rate in exchange for the ability to use your collateral while it is being held to secure some other debt or commitment. On the other side, your counterparty can incentivize you to choose them as a counterparty by providing you some access to the capital that they take as collateral. At the same time, they can charge an interest rate on this collateral in exchange for the added risk of allowing you to hold your collateral in some other asset. I would argue that this is a wildly preferable alternative to traditional fractional reserve banking.
  
One place where I believe this system could have a big impact is secured debt agreements. Debt is tricky on the blockchain, because there is no recourse against an address that disappears with loaned money. So, the current solution is fully secured debt. Unfortunately, this limits the potential applications of debt primarily to speculative leverage. Additionally, using debt to gain leverage on a speculative investment requires finding a counterparty willing to provide a loan of the asset that you want to leverage (or short) while accepting the same asset as collateral. Even with fully secured debt agreements, finding decentralized lending liquidity is no easy task. By allowing the collateral to be held in any token while still denominating the debt in the lender's preferred collateral type, decentralized debt starts to look a little more like a traditional debt agreement. Now, you can trade freely with both your loaned assets **and** the collateral itself. In the future, it could be possible to tokenize a real-world asset in a way that guarantees that the holder of the token is also in possession of the object, i.e. a tokenization of my house that also allows me to live in it and guarantees lenders that I am in possession of something of value. This tokenized asset could be held in an account as collateral for a loan while the loan itself is denominated in another asset altogether. Suddenly, decentralized debt begins to wield serious power.
