# Feature Specification: Em-Dash Phase Headers Fixture

**Feature Branch**: `006-emdash-phases`

**Created**: 2026-06-07

**Status**: Draft

## Overview

A spec whose `tasks.md` uses em-dash phase-header delimiters
(`## Phase N — <Name>`) — the canonical spec-kit heading style. After
the #34 broadening (spec 006), the parser accepts the em-dash, hyphen,
and bare-whitespace separators in addition to the colon, so these
headings parse to the same phase number + name the colon form would
have and DO produce task-phase sub-issues. Used to verify the broadened
grammar creates sub-issues for these headers and emits no near-miss
warning for them.
