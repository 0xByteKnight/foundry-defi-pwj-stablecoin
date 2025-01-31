# 🏦 PWJ Stablecoin – A Decentralized Algorithmic Stablecoin

![License](https://img.shields.io/badge/license-MIT-green)  
![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.28-blue)  
![Foundry](https://img.shields.io/badge/Built%20With-Foundry-orange)  

## 📌 Overview

**PWJ Stablecoin** is a decentralized, exogenously collateralized stablecoin that maintains a 1:1 peg to the US dollar. It is inspired by MakerDAO's **DAI**, but with a fully automated, governance-free approach. The protocol ensures that every PWJ token is overcollateralized with assets like **ETH** and **BTC**, and uses an algorithmic mechanism to maintain stability.  

This repository contains the smart contracts and the core logic for **minting, redeeming, and liquidating PWJ tokens**.

---

## ⚙️ Features

✔️ **Overcollateralized** – PWJ ensures security by maintaining a collateral ratio above 100%.  
✔️ **Decentralized Minting** – Users deposit collateral to mint stablecoins without intermediaries.  
✔️ **Liquidation Mechanism** – Maintains solvency by enforcing liquidations when the health factor is too low.  
✔️ **No Governance or Fees** – Operates autonomously based on predefined smart contract rules.  

---

## 🏗 Smart Contract Architecture

The system consists of the following core contracts:

### 🔹 [`DecentralizedStableCoin.sol`](contracts/DecentralizedStableCoin.sol)
- ERC20-compliant token that represents the PWJ stablecoin.
- Supports **minting** and **burning** by authorized contracts.

### 🔹 [`DSCEngine.sol`](contracts/DSCEngine.sol)
- Core logic for **collateral deposits, minting, redemptions, and liquidations**.
- Uses Chainlink oracles to fetch real-time price feeds.
- Ensures collateralization ratios and liquidates undercollateralized positions.

---

## 🚀 Installation & Setup

Ensure you have **Foundry** installed. If not, install it using:

```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 1️⃣ Clone the repository:

```sh
git clone https://github.com/0xByteKnight/foundry-defi-pwj-stablecoin.git
cd foundry-defi-pwj-stablecoin
```

### 2️⃣ Install dependencies:

```sh
forge install
```

### 3️⃣ Compile contracts:

```sh
forge build
```

### 4️⃣ Run tests:

```sh
forge test
```

---

## 📜 Usage

### 💰 Minting PWJ Tokens
Users can deposit **ETH** or **WBTC** as collateral and mint PWJ stablecoins.

```solidity
DSCEngine.depositCollateralAndMintDsc(ETH_ADDRESS, 10 ether, 5000 * 1e18);
```

### 🔥 Burning PWJ Tokens
To redeem collateral, users must first **burn** their PWJ tokens.

```solidity
DSCEngine.burnDsc(5000 * 1e18);
DSCEngine.redeemCollateral(ETH_ADDRESS, 10 ether);
```

### ⚠️ Liquidation
If a user's health factor falls below **1**, their collateral can be liquidated.

```solidity
DSCEngine.liquidate(WBTC_ADDRESS, USER_ADDRESS, 1000 * 1e18);
```

---

## 🏗 Development & Contribution

💡 Found a bug? Have an idea to improve the protocol? Contributions are welcome!  

### ✅ Steps to Contribute:
1. **Fork** this repository.  
2. **Create** a new branch: `git checkout -b feature-xyz`.  
3. **Commit** your changes: `git commit -m "Add feature xyz"`.  
4. **Push** to your fork and create a **Pull Request**.  

---

## 🔐 Security Considerations

- **Overcollateralization is required** to prevent system insolvency.
- **Oracles must provide accurate price feeds** to avoid mispricing.
- **Smart contracts should be audited** before deployment to mainnet.

---

## 📜 License

This project is licensed under the **MIT License** – feel free to use and modify it.  

---

## 🔗 Connect with Me  

💼 **GitHub**: [0xByteKnight](https://github.com/0xByteKnight)  
🐦 **Twitter/X**: [@0xByteKnight](https://twitter.com/0xByteKnight)  
