# Private Dues Status — FHEVM

**Tagline:** Amounts stay private. The only thing that is revealed is a yes/no **membership status** (In Good Standing / Overdue).

---

## Overview

This dApp manages **membership dues** without ever exposing amounts or payment details on‑chain. For each member, the contract stores only an **encrypted** `paidThrough` timestamp (epoch seconds). Status is computed as:

```
IN_GOOD_STANDING if (paidThrough + graceDays) ≥ now
else OVERDUE
```

Both the comparison and result are processed in FHE. The UI can return:

* a **private** encrypted result (only the caller can decrypt), or
* a **publicly decryptable** result (anyone can verify the status).

---

## Main Features

* **Encrypted storage** of `paidThrough` per member (no amounts or per‑payment breakdown).
* **Owner/Treasurer** roles to update `paidThrough` with attested encrypted inputs.
* **Public grace period** (days) to tolerate short delays, configurable by Owner.
* **Two status flows**:

  * **Private status** → `userDecrypt` (requires EIP‑712 signature by the caller).
  * **Public status** → `publicDecrypt` (globally readable once published).
* **Minimal, original UI/UX** with clear logs and Sepolia autoswitch.

---

## Prerequisites

* Browser wallet (MetaMask)
* Sepolia ETH for gas
* Node 18+ (optional; to run a local static server)

---

## Installation / Run

You may open the HTML directly, but running a local server is recommended for WASM workers and CORS.

```bash
# from the repository root
# Option A: npx http-server
npx http-server frontend/public -p 5173 --cors

# Option B: Python
python3 -m http.server --directory frontend/public 5173

# then open in a browser
http://localhost:5173
```

The app will:

1. Ask to **Connect Wallet** and switch to **Sepolia**.
2. Initialize the Relayer SDK 0.2.0.
3. Attach to contract `0x005f2A30fb7AB99245800C04BDc11F6c383d19F3` via Ethers v6.

---

## How to Use (Quick)

### Owner / Treasurer

1. **Set Grace Days** (public, non‑sensitive)

   * Enter integer days (e.g., `7`) → **Set Grace**.
2. **(Owner only) Set Treasurer**

   * Enter an address → **Set Treasurer**.
3. **Set PaidThrough (encrypted)**

   * Member Address `0x…` and **PaidThrough (epoch seconds)**, e.g., `1767139200` → **Set PaidThrough (encrypted)**.
   * The UI creates an encrypted input, gets a proof, and sends `setPaidThroughEncrypted(...)`.

### Anyone

* **Check Private**

  * Enter Member Address → **Check Private**.
  * UI parses `StatusCheckedPrivate` event, then performs **userDecrypt** via EIP‑712 signature.
* **Check Public**

  * Enter Member Address → **Check Public**.
  * Contract marks the result publicly decryptable; UI calls **publicDecrypt** and shows the final status.

Expected badge:

* ✅ `IN GOOD STANDING`
* ❌ `OVERDUE`

---

## Configuration

Edit constants at the top of `frontend/public/index.html` if needed:

* **CONTRACT_ADDRESS** (default: `0x005f2A30fb7AB99245800C04BDc11F6c383d19F3`)
* **RELAYER_URL** (default: `https://relayer.testnet.zama.cloud`)
* **CHAIN_ID_HEX** (default: Sepolia `0xaa36a7`)

---


