# Postmortem: <short title>

> Three of these, written honestly, are the most differentiating artifact in this
> repo. Almost nobody has them. Write them **when it happens**, not at the end —
> reconstructed postmortems read as reconstructed.
>
> Blameless: describe what the system allowed, not what you failed to do.

**Date:** YYYY-MM-DD
**Duration:** how long the bad state existed
**Impact:** what was broken, for whom, and what it cost (dollars if applicable)
**Author:** you

## Summary

Two or three sentences. Someone reading only this should understand what happened.

## Timeline

| Time (NZST) | Event |
|---|---|
| 14:02 | Change X merged |
| 14:07 | First symptom observed |
| 14:31 | Root cause identified |
| 14:40 | Mitigated |

## Root cause

The actual mechanism. Push past the first plausible explanation — "the cert
expired" is a symptom; "nothing alerted on cert expiry because the exporter was
scraping the wrong namespace" is a cause.

## Detection

How did you find out? If the answer is "I noticed by chance," that is itself a
finding worth an action item.

## What went well

Genuinely — the mitigations that worked are as informative as the failure.

## What went badly

## Action items

| Action | Type | Status |
|---|---|---|
| | prevent / detect / mitigate | |

Categorise each one. A list that is all "prevent" means you are not investing in
detection, which is a pattern worth noticing about yourself.

## Lessons

What you would tell someone building this from scratch. This is the paragraph an
interviewer will ask you to expand on, so make it a real opinion.
