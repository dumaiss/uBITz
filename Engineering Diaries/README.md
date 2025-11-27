# μBITz Engineering Diaries

This directory contains the day-by-day engineering log for the μBITz platform.

Each diary entry captures:

- **Decisions** – architecture and design choices that should be treated as “current truth”.
- **Constraints** – assumptions, external limits, and non-negotiables.
- **Rejected Ideas (and why)** – approaches we considered and discarded, plus the reasoning.
- **Open Questions** – unresolved items that need future design work.
- **Notes** – misc observations, implementation hints, and follow-ups.

## File naming

Diaries are stored as one file per day:

- `YYYY-MMM-DD-EngineeringDiary.md`

Example:

- `2025-NOV-26-EngineeringDiary.md`

This keeps entries sortable by date and easy to grep.

## How to use these diaries

- **Before making a change**  
  Skim the most recent diary file to see existing decisions and constraints that might affect your idea.

- **After a design session**  
  Add a new dated section (or a new file) and record:
  - What you decided
  - What you explicitly rejected
  - Any open questions or TODOs

- **When documenting specs/code**  
  Treat the diary as the “why” behind the specs and HDL/schematics. If a future you wonders *“why on earth did I do this?”*, the answer should be here.

## Cross-references

Where useful, link from diary entries to:

- Spec documents (e.g. Dock/Host/Bank/Tile specs)
- Schematic sheets (KiCad file names)
- Code modules (HDL / firmware paths)

This keeps the diary small but makes it the central index of μBITz design intent.
