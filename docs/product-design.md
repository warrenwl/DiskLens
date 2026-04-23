# DiskLens Product Design

## Product Positioning

DiskLens is a macOS disk visibility and safe-cleaning tool for AI and developer workflows.

The product should feel like a precise, minimal disk control panel rather than a generic cleaner. The primary value is confidence: users can see what consumes space, understand cleanup risk, and move only reviewed items to Trash.

## Design Principles

- **Minimal entry, focused tasks**: the first screen offers two clear paths only: Disk Panorama and One-Click Cleanup.
- **Visual first**: the disk panorama keeps the treemap as the main mental model for space usage.
- **Review before action**: cleanup candidates are grouped by risk and selected explicitly.
- **Trash, not delete**: all file cleanup actions move items to Trash; no permanent deletion in this iteration.
- **No hidden automation**: every executable cleanup must be visible before confirmation.
- **Default safe, manual risky**: safe cleanup and orphan app leftovers are selected by default; duplicates and large files are not.

## Home Screen

Layout:

```text
DiskLens logo + title

Left region:
  Heartbeat/disk health icon
  Welcome message
  Short status or value proposition

Right region:
  Large button: Disk Panorama
    Icon + one-line description
  Large button: One-Click Cleanup
    Icon + one-line description
```

Interaction:

- Disk Panorama opens the treemap experience.
- One-Click Cleanup starts a cleanup scan/preparation flow.
- No automatic scan should run on launch unless the user chooses an entry point.

## Disk Panorama Page

Purpose: inspect disk usage visually.

Layout:

```text
Top bar:
  Back to Home
  Scan scope selector
  Start/Stop scan
  Export
  History

Main:
  Left: treemap
  Right: selected item detail + recommendations

Bottom:
  searchable path table
```

Behavior:

- Reuse existing treemap drill-down, breadcrumb, selected item, and table workflows.
- Include a clear Home return action.
- Cleanup execution is not the focus of this page.

## One-Click Cleanup Page

Purpose: generate, review, and execute a safe cleanup plan.

Flow:

```text
Open One-Click Cleanup
-> prepare scan
-> show four cleanup sections
-> user adjusts selection
-> click One-Click Cleanup
-> confirmation dialog
-> move selected items to Trash
-> show completion summary
```

Top bar:

```text
Back to Home        One-Click Cleanup
                                      [One-Click Cleanup]
```

Preparation state:

```text
Scanning and preparing cleanup plan...
Current step: disk scan / app leftovers / duplicates
```

## Cleanup Sections

All sections are stacked vertically from top to bottom. Each section title has a section-level checkbox that selects or clears all candidates in that section.

### 1. Safe Cleanup

Default selected: yes.

Includes:

- safe cache paths
- rebuildable cache items
- low-risk temporary artifacts

Excludes:

- system paths
- protected app data
- user documents
- unknown large files

### 2. App Leftovers

Default selected: yes, but only safe leftovers.

Includes:

- orphan preferences
- orphan caches
- saved application state
- logs
- HTTP storage

Not default selected:

- Application Support
- Containers
- Group Containers
- WebKit
- Cookies

### 3. Duplicate Files

Default selected: no.

Behavior:

- keep one item per duplicate group by default
- candidate rows are duplicate copies only
- user must select duplicates manually

### 4. Large Files

Default selected: no.

Includes:

- large regular files above the configured threshold
- model files
- downloads
- archives

Behavior:

- never auto-select
- provide Finder reveal before cleanup

## Candidate Row Design

Each row:

```text
[checkbox]  file/app name       size       risk badge
            path
            short reason/action
```

Row actions:

- reveal in Finder
- copy path

No destructive row-level action in this iteration.

## Cleanup Confirmation

Dialog copy:

```text
Move selected items to Trash?

Selected:
- N items
- estimated size X GB

DiskLens will move selected files to Trash. It will not permanently delete files.
Review Trash before emptying it.

[Cancel] [Move to Trash]
```

Completion state:

```text
Cleanup complete
Moved N items to Trash
Estimated size: X GB
Failed: M items

[Reveal Trash] [Scan Again]
```

## Visual Style

- Flat layout, no nested cards.
- Use cards only for four cleanup sections and repeated row groups.
- Prefer macOS-native controls.
- Use color only for semantic risk:
  - green: safe
  - orange: review
  - red: destructive/high risk
  - blue: informational
  - gray: keep/system
- Treemap remains visually dominant on the panorama page.

