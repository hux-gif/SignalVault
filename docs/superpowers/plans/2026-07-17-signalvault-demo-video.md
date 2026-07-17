# SignalVault Final Demo Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record and verify a truthful 2:15–2:40 SignalVault Coston2 demo MP4 with PixPin, then leave the repository and submission copy ready for the user’s final DoraHacks upload.

**Architecture:** Treat the public execution dossier as the only recorded product surface. Keep the MP4 and cover image outside Git, use PixPin normal recording for trim-and-preview support, verify the exported file independently through Windows media metadata and playback, then update only submission documentation with the already-verified frontend release facts.

**Tech Stack:** PixPin 3.3.5.7, Microsoft Edge or Chrome fullscreen mode, GitHub Pages, PowerShell, Git, GitHub Actions

## Global Constraints

- Use `https://hux-gif.github.io/SignalVault/` as the recorded source.
- Record MP4 at 30 FPS, original quality, 16:9, targeting 1920x1080.
- Keep duration between 2 minutes 15 seconds and 2 minutes 40 seconds.
- Disable microphone and system audio.
- Keep the cursor visible.
- Never open MetaMask, request an account, display a wallet address, or send a transaction.
- Never expose private keys, `.env` files, notifications, unrelated tabs, terminals, or source editors.
- Do not claim hardware TEE, production security, mainnet deployment, audited status, guaranteed yield, or external user traction.
- Do not modify Solidity, TypeScript, frontend production code, deployments, or evidence reports.
- Keep the MP4 and cover image outside Git under `D:\SignalVault-submission`.
- Push only to `origin/main`; do not create or retain another remote branch.
- The user owns video hosting and the final DoraHacks submission action.

---

### Task 1: Prepare a clean recording surface

**Files:**
- Read: `docs/superpowers/specs/2026-07-17-signalvault-demo-video-design.md`
- Read: `docs/submission/demo-script.md`
- Create outside Git: `D:\SignalVault-submission\`

**Interfaces:**
- Consumes: the deployed dashboard URL and the approved shot sequence
- Produces: a clean fullscreen browser surface and empty output directory

- [ ] **Step 1: Verify repository and remote baseline**

Run:

```powershell
cd D:\xhy.worktrees\signalvault-final
git status --short
git rev-parse HEAD
git fetch origin --prune
git rev-parse origin/main
```

Expected: the worktree is clean, local HEAD contains the approved design commit, and `origin/main` is still `028947bcad9f129fd5ccf77669fc03528c5e9b14` before the documentation commits are pushed.

- [ ] **Step 2: Create a clean output directory**

Run:

```powershell
New-Item -ItemType Directory -Force D:\SignalVault-submission
Get-ChildItem D:\SignalVault-submission -Force
```

Expected: the directory exists. Remove only failed SignalVault takes created during this task; do not delete unrelated files.

- [ ] **Step 3: Validate the live dashboard**

Open `https://hux-gif.github.io/SignalVault/` and verify:

```text
Private strategy. Public proof.
Coston2 RPC live
four canonical transaction rows
Execution receipt
Mode B disclosure
```

Expected: the page renders with no blank screen, no ABI parsing exception, and no page-console error.

- [ ] **Step 4: Prepare the browser**

Close unrelated tabs and notifications, open the dashboard in a dedicated browser window, switch to fullscreen, return to the hero, and confirm no account address or personal browser UI is visible.

Expected: the recording surface contains only the SignalVault dashboard.

### Task 2: Record and export the approved PixPin take

**Files:**
- Create outside Git: `D:\SignalVault-submission\SignalVault-demo.mp4`
- Create outside Git: `D:\SignalVault-submission\SignalVault-demo-cover.png`

**Interfaces:**
- Consumes: the clean browser surface from Task 1 and PixPin normal recording
- Produces: the final MP4 and cover image

- [ ] **Step 1: Open PixPin recording mode**

Use PixPin’s screenshot action, select the 16:9 browser content area, and choose normal screen recording. Set 30 FPS, original quality, visible cursor, microphone off, system audio off, and a three-second start delay.

Expected: the PixPin region border encloses only the fullscreen dashboard and shows the waiting state.

- [ ] **Step 2: Record the product thesis and verified run**

Start the recording and follow this exact sequence:

```text
0:00-0:15  hero and verified facts
0:15-0:55  transaction ledger; select Deposit, Commitment, Execution, Withdrawal
```

Expected: every selected row updates the Execution Receipt and no external wallet or Explorer page opens.

- [ ] **Step 3: Record the privacy, accounting, and wallet boundaries**

Continue:

```text
0:55-1:20  disclosure boundary
1:20-1:45  live net NAV, gross NAV, available liquidity and exposures
1:45-2:00  open wallet verification drawer, show the three no-side-effect statements, close drawer
```

Expected: the drawer is opened but `Browser Wallet` is not selected.

- [ ] **Step 4: Record controls, contracts, and the honest close**

Continue:

```text
2:00-2:25  control table and five deployed addresses
2:25-2:40  Mode B disclosure and Coston2 testnet warning
```

Stop recording while the final disclaimer remains visible.

Expected: the take contains no unrelated application, notification, address popup, or secret.

- [ ] **Step 5: Trim and export**

In PixPin playback, remove only inactive frames before the hero and after the final disclaimer. Preview from beginning to end, select MP4, and save exactly as:

```text
D:\SignalVault-submission\SignalVault-demo.mp4
```

Expected: PixPin reports a successful save and the file exists with a nonzero size.

- [ ] **Step 6: Capture the cover**

Return to the dashboard hero, use PixPin static capture on the same 16:9 region, and save exactly as:

```text
D:\SignalVault-submission\SignalVault-demo-cover.png
```

Expected: the cover shows “Private strategy. Public proof.” and contains no browser or wallet identity.

### Task 3: Verify the exported artifacts

**Files:**
- Inspect: `D:\SignalVault-submission\SignalVault-demo.mp4`
- Inspect: `D:\SignalVault-submission\SignalVault-demo-cover.png`

**Interfaces:**
- Consumes: Task 2 artifacts
- Produces: verified file metadata and visual playback evidence

- [ ] **Step 1: Verify file presence and size**

Run:

```powershell
Get-Item D:\SignalVault-submission\SignalVault-demo.mp4,
         D:\SignalVault-submission\SignalVault-demo-cover.png |
  Select-Object FullName,Length,LastWriteTime
```

Expected: both files exist and each length is greater than zero.

- [ ] **Step 2: Read Windows media metadata**

Run:

```powershell
$folder = 'D:\SignalVault-submission'
$shell = New-Object -ComObject Shell.Application
$namespace = $shell.Namespace($folder)
$item = $namespace.ParseName('SignalVault-demo.mp4')
[pscustomobject]@{
  Duration = $item.ExtendedProperty('System.Media.Duration')
  Width = $item.ExtendedProperty('System.Video.FrameWidth')
  Height = $item.ExtendedProperty('System.Video.FrameHeight')
  FrameRate = $item.ExtendedProperty('System.Video.FrameRate')
}
```

Expected: duration is 135–160 seconds, aspect ratio is 16:9, height is at least 1080 when the display permits it, and frame rate resolves to approximately 30 FPS.

- [ ] **Step 3: Perform complete playback review**

Open the exported MP4 in the system video player and watch it from start to finish at normal speed.

Expected: text is legible, transitions are deliberate, all required sections appear, and the video contains no private or unrelated content. If any acceptance criterion fails, delete only the failed take, re-record Task 2, and repeat Task 3.

- [ ] **Step 4: Review the cover**

Open the PNG and confirm the hero is sharp, centered, 16:9, and free from personal browser UI.

Expected: cover is ready for a video host or DoraHacks media field.

### Task 4: Finalize the submission documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/status/current-product-state.md`
- Modify: `docs/submission/judge-checklist.md`
- Modify: `docs/submission/demo-script.md`
- Create: `docs/submission/final-submission-copy.md`

**Interfaces:**
- Consumes: verified artifact names, frontend release commit `028947bcad9f129fd5ccf77669fc03528c5e9b14`, Verify run `29501160815`, Deploy frontend run `29501161290`, and 207 passing JavaScript/TypeScript tests
- Produces: current English copy that the user can paste into DoraHacks

- [ ] **Step 1: Update stale release facts**

Replace references to `signalvault-final`, `f013cdb1`, 182 tests, six frontend tests, and “Demo video: pending upload” with:

```text
Repository branch: main
Frontend release commit: 028947bcad9f129fd5ccf77669fc03528c5e9b14
Verify workflow: https://github.com/hux-gif/SignalVault/actions/runs/29501160815
Deploy frontend workflow: https://github.com/hux-gif/SignalVault/actions/runs/29501161290
JavaScript/TypeScript tests: 207 total — 109 local-signer, 31 frontend, 67 integration
Demo video: recorded locally; public upload remains a user-owned action
```

Do not change deployment addresses, transaction hashes, Mode B disclosures, or known limitations.

- [ ] **Step 2: Create the paste-ready submission copy**

Create `docs/submission/final-submission-copy.md` with these exact sections:

```text
Project name
Tagline
Short description
Full description
Primary bounty
Secondary bounty
Repository URL
Live demo URL
Demo video URL — user upload required
Coston2 deployment addresses
Four canonical transaction links
Testing and verification
Existing work versus hackathon work
Known limitations
Final human submission checklist
```

Reuse only verified facts from `docs/submission/project-description.md`, `docs/submission/bounty-1.md`, `docs/submission/bounty-2.md`, `docs/submission/existing-vs-new.md`, and `docs/submission/known-limitations.md`.

- [ ] **Step 3: Audit the documentation diff**

Run:

```powershell
git diff --check
git diff -- README.md docs/status/current-product-state.md docs/submission
rg -n "signalvault-final|f013cdb1|182 tests|6 frontend|pending upload" README.md docs/status docs/submission
```

Expected: `git diff --check` exits 0, changed copy is English and fact-consistent, and the stale-value search returns no active release claim.

- [ ] **Step 4: Commit the submission documentation**

Run:

```powershell
git add README.md docs/status/current-product-state.md docs/submission
git diff --cached --check
git commit -m "docs: finalize SignalVault submission package"
```

Expected: only submission documentation is committed; MP4 and PNG are not staged.

### Task 5: Final verification and main-only publication

**Files:**
- Verify only; no production file changes

**Interfaces:**
- Consumes: committed documentation and previously verified production release
- Produces: updated `origin/main` and a final user handoff

- [ ] **Step 1: Run scope and secret audits**

Run:

```powershell
git status --short
git show --stat --oneline HEAD
git diff 028947bcad9f129fd5ccf77669fc03528c5e9b14..HEAD -- src frontend local-signer integration script deployments reports
git ls-files | Select-String -Pattern '(^|/)(\.env|.*private.*key.*)$'
```

Expected: the production-path diff is empty, no video is tracked, and no secret file is introduced.

- [ ] **Step 2: Reconfirm the deployed dashboard and workflows**

Verify that the live page still loads the release bundle and that the Verify and Deploy frontend workflows for `028947b` remain completed successfully.

- [ ] **Step 3: Synchronize and push only main**

Run:

```powershell
git fetch origin --prune
git rev-list --left-right --count 028947bcad9f129fd5ccf77669fc03528c5e9b14...origin/main
git push origin HEAD:main
```

Expected before push: `origin/main` has not moved beyond `028947b`. Expected after push: the new documentation commits are on `origin/main` without force push.

- [ ] **Step 4: Confirm the public branch set**

Query the GitHub repository branch API and confirm:

```text
default branch = main
remote branches = [main]
```

- [ ] **Step 5: Hand off the submission package**

Report:

```text
MP4 absolute path and byte size
cover absolute path and byte size
duration, resolution and frame rate
recording review result
repository commit sequence
origin/main SHA
submission copy path
live dashboard URL
remaining user actions: upload video, paste URL, submit DoraHacks form
```

Do not upload the video or press the final DoraHacks submission button.
