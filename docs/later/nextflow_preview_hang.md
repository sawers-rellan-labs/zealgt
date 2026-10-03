# Nextflow `-preview` never exits

On Nextflow 26.04.6, `nextflow run . -profile test -stub -preview -with-dag dag.mmd` logs "Pipeline completed
successfully" and then hangs: operators stay active waiting for process output that preview never makes. The DAG is
written only when the run is killed, with unindexed nodes (`v-1`, a different count each run) on which
`MermaidRenderer.getNodeLookup` throws a NullPointerException. Seen on `dev` (ff712a6) and Milestone 4.

Workaround in use: the DAG from a stub run (`docs/running.md`, "The DAG").

Later: a minimal pipeline (one process, `channel.topic`, a workflow `output` block) run with `-preview -with-dag x.mmd`;
if it hangs, open an issue at nextflow-io/nextflow with it. No issue matched on 2026-10-03 (searched `MermaidRenderer`,
the NPE text, "dag preview hang").
