---
phase: 14
title: Anthropometric ergonomics
status: planning
---

# Phase 14: Anthropometric ergonomics

## Background
The app already tracks the user's height (`heightCm`). However, height and body proportions (limb length, torso length) drastically change how a user should perform big compound movements (like a back squat or deadlift). Currently, users are left wondering why their form doesn't match standard instructional videos if their proportions don't match the "average" lifter.

## Goal
Use the height the profile already stores — and limb measurements if the user offers them — to tell people which variant of a big compound suits their proportions.

## Requirements (ERG-01–03)
- **ERG-01**: Profile height, plus optional inseam, arm span and torso measurements, yield proportion ratios.
- **ERG-02**: Movements carry variant guidance keyed to those proportions, with sources recorded.
- **ERG-03**: Guidance appears on the exercise and through Hercul, is absent when measurements are unknown, and is phrased as a trade-off rather than a correction.

## Scope fence
Height and optional tape measurements only. No video, no pose estimation, no form scoring.
