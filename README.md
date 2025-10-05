# 🧪 Presale Smart Contract

**Presale** is a Solidity smart contract designed for token presales with support for multiple stablecoins, ETH purchases, time-based sale phases, and full on-chain reward distribution.
The project includes a comprehensive Foundry test suite achieving **100% coverage**.

> **Note**
> All tests run against an **Arbitrum One fork**, ensuring real-world compatibility with live ERC20s and Chainlink data feeds.

---

## 🔹 Key Features

* ✅ Token sale via **USDT**, **USDC**, or **ETH**.
* ✅ Multi-phase system with thresholds and deadlines.
* ✅ Real-time price conversion using **Chainlink ETH/USD feed**.
* ✅ Blacklist and whitelist mechanisms.
* ✅ Full test coverage with **Foundry** and **mocks**.
* ✅ Emergency withdrawal functions for both **ETH** and **ERC20** assets.

---

## 📄 Deployed Environment

| 🔧 Item                | 📋 Description                                                                                                         |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Network**            | Arbitrum One                                                                                                           |
| **ETH/USD Price Feed** | [`0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612`](https://arbiscan.io/address/0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612) |
| **USDT Address**       | [`0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9`](https://arbiscan.io/token/0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9)   |
| **USDC Address**       | [`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`](https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831)   |

---

## 🚀 Local Setup

### 1️⃣ Clone the repository

```bash
git clone https://github.com/yourusername/presale-contract.git
cd presale-contract
```

### 2️⃣ Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 3️⃣ Run the tests

Create a `.env` file and add your Arbitrum RPC:

```
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
```

Then run:

```bash
forge test --fork-url $ARBITRUM_RPC_URL -vvv
```

---

## 🧪 Test Summary

| File                           | % Lines  | % Statements | % Branches | % Functions |
| ------------------------------ | -------- | ------------ | ---------- | ----------- |
| `src/Presale.sol`              | **100%** | **100%**     | **96%**    | **100%**    |
| `test/Presale.test.sol`        | **100%** | **100%**     | **100%**   | **100%**    |
| `test/mocks/MockSaleToken.sol` | **100%** | **100%**     | **100%**   | **100%**    |
| **Total**                      | **100%** | **100%**     | **96%**    | **100%**    |

> ✅ Achieved full coverage across all functionalities using `forge coverage`.

---

## 🧠 Test Coverage Breakdown

**Covered functions:**

* `constructor(...)` (all reverts and success path)
* `buyWithStable(...)` — including invalid token, blacklist, timing, phase advance, and over-limit checks
* `buyWithEther()` — includes oracle integration, reverts, and success transfers
* `checkCurrentPhase()` — all logical branches (`threshold`, `deadline`, `combined`)
* `claim()` — before and after presale end, zero-balance protection
* `emergencyERC20Withdraw()` and `emergencyETHWithdraw()` — both owner and non-owner paths
* `getEtherPrice()` — oracle value validation

---

## 🛠️ Project Structure

```
presale/
├── src/
│   └── Presale.sol
├── test/
│   ├── Presale.test.sol
│   ├── mocks/
│   │   ├── MockSaleToken.sol
│   │   ├── MockStableToken18.sol
│   │   └── ReceiverMock.sol
├── foundry.toml
└── README.md
```

---

## 🧪 Highlights

* Built and tested on **Foundry** with **Arbitrum forked state**.
* **Comprehensive edge case testing** (constructor, blacklists, deadlines, oracles).
* **Gas-efficient structure** using `SafeERC20` and `Ownable`.
* **Decimals normalization logic** tested for 6 and 18 decimal stables.

---

## 📜 License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

### 🚀 Presale Smart Contract — Secure, tested, and ready for deployment.
