# Later: zealbc1's `inconsistent` flag in tier A

Milestone 7 follows its spec: tier A = LLR >= 6.9, ALT reads in >= 2 BC1 pools, no `hidepth` or `af_gt_half` flag
(user, 2026-10-04). zealbc1 also kept `inconsistent` sites out of tier A, so tier-A counts will differ from zealbc1.

## zealbc1's rule

`zealbc1/PHG/bin/pilot_step4_postfilter_llr.py` (lines 111-115): for a donor with more than one pool, `inconsistent` if
one pool has >= 3 ALT reads while another has >= 10 reads and 0 ALT. It blocks tier A only; tier B ignores it.

## How to add it back

- `bin/score_pooled_likelihood.py`: add `inconsistent` to the flags with two options, `--inconsistent_min_alt 3` and
  `--inconsistent_min_depth 10`, and check it only in the tier-A condition, not in `tier_of`'s tier-B branch.
- `conf/modules.config`: pass both values in `POOLED_LIKELIHOOD_TIERS`'s `ext.args`, like the other step-4 values.
- Unit test: a fixture with one pool at a = 3 and another at n = 10, a = 0: tier B, flag `inconsistent`.
