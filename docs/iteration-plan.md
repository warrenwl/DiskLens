# DiskLens Iteration Plan

## Current State

Implemented foundations:

- disk scan and treemap
- scan cache and history
- structured cleanup commands
- duplicate detection with staged hashing
- app leftover detection
- safe app leftover cleanup via Trash
- scan progress phases
- scan tree indexing

Known issue from product/design review:

- cleanup features were added into the existing layout before the product flow was redesigned.
- next iteration should prioritize screen-level information architecture before adding more cleanup power.

## Iteration 1: Home + Navigation Restructure

Goal: introduce a minimal app shell with two primary entry points.

Scope:

- Add app screen state: home, panorama, cleanup.
- Home screen with:
  - top-left logo/title
  - left heartbeat-style health visual
  - welcome text
  - right-side large action buttons:
    - Disk Panorama
    - One-Click Cleanup
- Stop auto-scanning on launch.
- Add Back to Home on non-home screens.

Acceptance:

- app opens to the home screen
- Disk Panorama opens existing treemap workflow
- One-Click Cleanup opens cleanup preparation workflow
- no cleanup action is possible from the home screen

## Iteration 2: Disk Panorama Page

Goal: keep existing treemap behavior while improving layout clarity.

Scope:

- Move current scan toolbar into panorama page.
- Preserve:
  - scan mode picker
  - custom directory selection
  - start/stop scan
  - export menu
  - history sheet
  - treemap drill-down and breadcrumb
  - selected item detail
  - table search/filter/sort
- Remove cleanup-specific buttons from panorama toolbar.

Acceptance:

- existing treemap workflows still work
- user can return to Home
- user can export reports from Panorama
- cleanup plan is not mixed into the treemap page

## Iteration 3: One-Click Cleanup Preparation

Goal: generate a reviewable cleanup plan before any action.

Scope:

- One-Click Cleanup entry starts preparation:
  - disk scan if no current scan result exists
  - app leftover scan
  - duplicate detection
  - large file candidate generation
- Show preparation status.
- Generate four cleanup sections:
  - Safe Cleanup
  - App Leftovers
  - Duplicate Files
  - Large Files

Acceptance:

- cleanup page can prepare from a cold launch
- preparation can reuse existing scan result
- user sees four sections after preparation
- safe/app-leftover sections are selected by default
- duplicate/large file sections are not selected by default

## Iteration 4: Selection Model

Goal: make cleanup selection explicit and predictable.

Scope:

- Candidate row with checkbox, size, path, risk, reason.
- Section title checkbox:
  - select all
  - clear all
- Track selected item count and selected bytes.
- Prevent selecting high-risk/system items unless intentionally included in future scope.

Acceptance:

- individual item selection works
- section-level select/clear works
- selected total updates immediately
- duplicate and large file candidates are initially unselected

## Iteration 5: Trash-Based Cleanup Execution

Goal: perform safe cleanup only after confirmation.

Scope:

- Top-right One-Click Cleanup button on cleanup page.
- Disabled unless at least one candidate is selected.
- Confirmation dialog summarizing:
  - item count
  - estimated bytes
  - Trash-only behavior
- Move selected candidates to Trash.
- Show completion summary:
  - moved count
  - estimated bytes
  - failures
- Remove cleaned items from current plan after success.

Acceptance:

- no permanent deletion is used
- selected files move to Trash
- failed items remain visible
- cleanup can be cancelled before confirmation

## Iteration 6: Verification and Packaging

Goal: keep the app shippable after layout changes.

Required checks:

- `swift run DiskLensChecks`
- `swift build`
- `git diff --check`
- `bash scripts/build_app_bundle.sh`

Package output:

- project-root `DiskLens.app`

Manual QA:

- Home loads without scanning.
- Disk Panorama starts scan and shows treemap.
- Cleanup from cold launch prepares all sections.
- Section and row checkboxes behave correctly.
- One-Click Cleanup confirmation appears.
- Selected safe test item moves to Trash.
- Back to Home works from Panorama and Cleanup.

## Deferred

Do not include in this redesign iteration:

- permanent delete
- root escalation
- Docker prune execution
- automatic model deletion
- automatic duplicate deletion
- cleaning Application Support or Containers by default
- notarization/codesign

