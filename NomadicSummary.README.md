# NomadicSummary WDL

## Overview

`NomadicSummary.wdl` runs a single `NomadicSummary` workflow that collects zipped
`nomadic` outputs, runs `nomadic summarize` across them, and copies the summary
result to GCS.

High-level behavior:

- Unzips every file in `zipped_outputs` into a shared directory on the VM.
- Each zip is expected to extract to `results/{experiment_name}/` (matching how
  `Nomadic.wdl` produces `outputs.zip`); those experiment directories are
  collected and passed as positional arguments to `nomadic summarize`.
- Runs `nomadic summarize` with `--metadata_csv`, `--summary_name`,
  `--no-dashboard`, and `--output-dir output/`.
- Zips the `output/` directory and uploads it (via `gcloud storage cp`) to:
  - `gs://{bucket}/summarize/output/{summary_name}/{YYYY_MM_DD_HH_MM}/`

## Inputs

| input name            | required | type         | default                                            | notes                                                                             |
|-----------------------|----------|--------------|-----------------------------------------------------|------------------------------------------------------------------------------------|
| `zipped_outputs`      | yes      | `Array[File]`| none                                                | Zipped `nomadic` outputs (e.g. `Nomadic.wdl`'s `zipped_output_file`) to summarize. |
| `samples_to_include`  | yes      | `File`       | none                                                | GCS path to a one-column CSV with header `sample_id`. Used as `--metadata_csv`.   |
| `summary_name`        | yes      | `String`     | none                                                | Used as `--summary_name` and in the GCS output path.                              |
| `output_bucket_name`  | yes      | `String`     | none                                                | Bucket root for final outputs. Accepts with or without `gs://`.                   |
| `memory_gb`           | no       | `Int`        | `4`                                                 | Task runtime memory in GB.                                                        |
| `disk_gb`             | no       | `Int`        | `100`                                               | Task runtime local disk size in GB.                                               |
| `docker_name`         | no       | `String`     | `us.gcr.io/broad-gotc-prod/nomadic:latest`         | Docker image used to run `nomadic summarize`.                                     |

## Outputs

| output name          | required | type     | default               | notes                                                                       |
|-----------------------|----------|----------|------------------------|------------------------------------------------------------------------------|
| `zipped_output_file`  | yes      | `String` | generated at runtime   | GCS path to the zipped summary output.                                      |
| `unzipped_output_dir` | yes      | `String` | generated at runtime   | Local VM path to the unzipped `nomadic summarize --output-dir` directory (only valid on the task's VM during execution). |
