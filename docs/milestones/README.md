# Milestones

Work is done one milestone at a time; each has a one-page spec in this folder (`NN_<name>.md`). A milestone builds a
stage (a row in `../structure.md`); a run of built stages on real data has a run plan in `../runs/`.

## Before: the spec (the user approves it)

- Why: the user's reason for the milestone, in their words. A row in `../structure.md`, a handover or an old repository's
  feature is not a reason; without one on record, ask whether the milestone is needed before writing the spec.
- Inputs and outputs, with file names and samplesheet columns.
- Tools and settings, taken from `../decisions.md`.
- The choices the spec settles, each with the rejected alternative.
- Tests: wiring on stubs (laptop, seconds, with the channel-level DAG), tool tests on fixtures (laptop), a stub run on
  hazel, and a resource profile on hazel (<= 30 min per process); laptop tests together <= 5 min.
- Done when: the checks that close the milestone.

## During: the agent works alone

- Native first: every mechanism names the Nextflow / nf-core feature that does it, or says why none fits.
- Every choice the spec left open is logged with the option rejected.
- Stop and ask only when a choice would change outputs or the spec.

## After: the report (the user reviews it)

- The diff.
- The DAG of what ran (`-preview -with-dag` and the run's `pipeline_dag`).
- Test results and resource numbers.
- The list of choices made during the work.
