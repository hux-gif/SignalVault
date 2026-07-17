# SignalVault Final Demo Video Design

## Goal

Produce a concise, truthful MP4 walkthrough of the deployed SignalVault Coston2 execution dossier. The video must give a judge enough evidence to understand the product, inspect the verified run, and recognize the privacy and trust boundaries without exposing a wallet address, private key, browser profile, or local development secret.

## Deliverables

- `D:\SignalVault-submission\SignalVault-demo.mp4`
- `D:\SignalVault-submission\SignalVault-demo-cover.png`
- An updated repository submission pack containing the final repository, deployment, verification, dashboard, and an explicit user-owned video upload field.

The MP4 and cover image remain outside Git. The user uploads the MP4 and completes the final DoraHacks submission.

## Recording Format

- Tool: PixPin 3.3.5.7 normal screen recording
- Container: MP4
- Frame rate: 30 FPS
- Quality: original
- Canvas: 16:9, targeting 1920x1080
- Duration target: 2 minutes 15 seconds to 2 minutes 40 seconds
- Audio: disabled
- Cursor: visible
- Browser: fullscreen with personal tabs, bookmarks, notifications, and wallet popups excluded
- Source: `https://hux-gif.github.io/SignalVault/`

Normal recording is selected instead of quick recording because it permits previewing and trimming the beginning and end before MP4 export.

## Visual Structure

### 0:00-0:15 — Product thesis

Show the hero and the exact message:

> Private strategy. Public proof.

Pause long enough to read the product summary, Coston2 network, verified deposit, allocation, and exit evidence.

### 0:15-0:55 — Verified execution

Scroll to the four-transaction ledger. Select Deposit, Private commitment, Execution, and Withdrawal in order so the adjacent Execution Receipt changes for each canonical transaction. Keep the Explorer hashes visible but do not navigate away from the dashboard during the core take.

### 0:55-1:20 — Privacy boundary

Show the “Remained private” and “Became public” columns. Hold on the statement that the original strategy stayed offchain while the salted commitment and signed allocation became public.

### 1:20-1:45 — Live vault state

Show the live Coston2 RPC status and the separate net NAV, gross NAV, available liquidity, Idle exposure, Upshift exposure, and protocol status values. The video must not imply guaranteed yield or mainnet readiness.

### 1:45-2:00 — Wallet verification boundary

Open the wallet-verification drawer and show that verification sends no transaction, requests no signature, and stores no address. Do not continue into an account request or display a wallet popup. Close the drawer before continuing.

### 2:00-2:25 — Constraints and deployment evidence

Show the signed-result control table and the five deployed Coston2 contract addresses. Hold briefly on chain binding, Vault binding, `routerConfigHash`, replay protection, and loss/deviation limits.

### 2:25-2:40 — Honest close

End on the Mode B disclosure and the testnet warning:

> Mode B is a software-isolated signer path. It is not a hardware-backed TEE.

The final frame must also show that the deployment is Coston2 testnet only, unaudited, and not for real funds.

## Interaction Rules

- Use deliberate scrolling with short reading pauses; do not rapidly scrub the page.
- Use only the dashboard’s real interactive controls.
- Do not stage fake transactions, balances, wallet states, toasts, or Explorer receipts.
- Do not open MetaMask or expose an account address.
- Do not show the desktop, terminal, source editor, private keys, `.env` files, notifications, or unrelated browser tabs.
- Do not claim hardware TEE, production security, mainnet deployment, audited status, guaranteed yield, or external user traction.
- If the live RPC degrades during the take, stop and re-record rather than presenting the recorded fallback as live state.

## Recording Procedure

1. Confirm the live dashboard loads without console errors and reports Coston2 live.
2. Close unrelated windows and notifications.
3. Open the dashboard in a clean fullscreen browser window and return to the hero.
4. Start a PixPin normal recording with a three-second delay.
5. Follow the shot sequence once without opening a wallet account request.
6. Stop recording, trim only the inactive beginning and ending, and preview the complete take.
7. Export MP4 to the submission directory.
8. Re-open the exported MP4 and verify duration, dimensions, video stream, readable text, and absence of private information.
9. Capture the hero as the cover image.

## Acceptance Criteria

- MP4 opens and plays from beginning to end.
- Duration is between 2:15 and 2:40.
- Video is 16:9 and at least 1080 pixels high when the display supports it.
- The hero, four transaction rows, Execution Receipt, privacy boundary, live vault state, wallet drawer, control table, deployed addresses, Mode B disclosure, and testnet warning are legible.
- The live page shows no blank screen or ABI parsing error.
- No wallet address, wallet popup, key, secret, notification, or unrelated application appears.
- All economic and confidential-compute claims remain within the repository’s verified fact boundary.
- Repository submission documentation is updated to `main` and the final release commit after the recording artifacts are verified.

## Explicit Non-Goals

- Uploading the video to a hosting service
- Logging into or submitting the DoraHacks form
- Sending a blockchain transaction
- Re-deploying any contract
- Modifying production Solidity or frontend behavior
- Claiming external feedback that has not occurred
