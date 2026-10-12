# Contributing to My CRM

## Repository

- **GitHub:** https://github.com/andrewsoulier/My_CRM
- **Recommended clone:** `~/My_CRM` (`gh repo clone andrewsoulier/My_CRM ~/My_CRM`)

The older path `~/My_CRM Project/MY CRM` is the same project history; prefer `~/My_CRM` for day-to-day git work to avoid spaces in paths and stray files in the parent folder.

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Stable, releasable app source. Merge via PR from `develop`. |
| `develop` | Integration branch for ongoing work. Check this out for features and fixes. |

```bash
cd ~/My_CRM
git checkout develop
git pull origin develop
# work, commit, push
git push origin develop
# open PR: develop → main when ready to release
```

Delete stale remote branches (for example `cursor/*` scaffolds) after confirming they are obsolete.

## What lives in git vs on disk

**In this repo:** Swift/macOS app, SPM `Package.swift`, scripts, tests, docs, `Resources/quick_send_helper.sh`.

**Not in this repo (local/runtime only):**

- `~/Library/Application Support/My_CRM/` — `my_crm.db`, listener config/state, logs
- Parent `~/My_CRM Project/` — DMGs, backup databases, side folders
- Life OS message listener — `~/life-os/scripts/message_listener/`

Never commit databases, DMGs, `.build/`, or `build/` output (see `.gitignore`).

## Build and test locally

```bash
cd ~/My_CRM
swift build
swift test
./Tests/run_tests.sh all
./build_app.sh "Local dev build"
```

CI runs the same commands from the **repository root** (no nested `My CRM/` directory).

## Pull requests

- Target `develop` for normal changes; target `main` only for release/hotfix flows agreed in advance.
- Keep commits focused; mention behavior changes in the PR description.
- If you change Quick Send or scheduling, note that post-schedule verification is documented in Life OS / the my-crm Cursor skill.
