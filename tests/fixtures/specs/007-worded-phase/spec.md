# Feature Specification: Worded-Number Phase Header Fixture

**Feature Branch**: `007-worded-phase`

**Created**: 2026-06-07

**Status**: Draft

**Input**: User description: "A tasks.md whose phase header writes the
number as a word (`## Phase one: Setup`). No separator rule can rescue
it — the grammar requires a digit run — so it stays a near-miss (US2),
preserving the no-silent-skips guarantee."

## Overview

A spec whose `tasks.md` writes a phase number as a word
(`## Phase one: Setup`). The broadened parser (spec 006) accepts colon,
em-dash, hyphen, and whitespace separators but still requires the phase
NUMBER to be a digit run, so a worded number remains unparseable. Used
to verify the near-miss WARNING still fires for genuinely unparseable
`## Phase` lines (FR-004/FR-005) after the grammar broadening.
