# NomadicSummary WDL

## Overview

`NomadicSummary.wdl` runs a single `NomadicSummary` workflow that collects zipped
`nomadic` outputs, runs `nomadic summarize` across them, copies the summary
result to GCS, and uploads a sample-centric table of amino acid calls to Terra.

High-level behavior:

- **`Summarize` task**
  - Unzips every file in `zipped_outputs` into a shared directory on the VM.
  - Each zip is expected to extract to `results/{experiment_name}/` (matching how
    `Nomadic.wdl` produces `outputs.zip`); those experiment directories are
    collected and passed as positional arguments to `nomadic summarize`.
  - Runs `nomadic summarize` with `--metadata_csv`, `--summary_name`,
    `--no-dashboard`, and `--output-dir output/`.
  - Copies both the unzipped `output/` directory and a zip of it (via
    `gcloud storage rsync`/`gcloud storage cp`) to:
    `gs://{bucket}/summarize/output/{summary_name}/{YYYY_MM_DD_HH_MM}/`
  - Surfaces `output/variants/aa_changes*.csv` (nomadic's per-sample variant
    calls) as a task output, for `UploadChangesToTerra` to consume.
- **`UploadChangesToTerra` task** (runs `scripts/combine_change_files_to_terra.py`
  in the image's isolated `terra_upload` conda env - see `Dockerfile`)
  - Combines all `aa_changes_files` into one per-change TSV and uploads it to
    `gs://{bucket}/summarize/output/{summary_name}/{YYYY_MM_DD_HH_MM}/change.tsv`
    (this data is no longer uploaded to Terra as its own table).
  - Pivots the same combined data into one row per `sample_id`, with a column
    per unique `aa_change_<gene>_<aa_change>` valued with that sample's
    `aa_call` (most rows will be missing most change columns - a sample only
    has a value for changes actually observed in it).
  - Deletes the existing Terra `sample` table (if any) and re-uploads the fresh
    pivoted data, so `sample` always reflects only the current run - and
    uploads the same data again to a dated copy (`sample_{YYYY_MM_DD_HH_MM}`)
    that's never deleted, preserving each run's table.

## Inputs

| input name            | required | type         | default                                            | notes                                                                             |
|-----------------------|----------|--------------|-----------------------------------------------------|------------------------------------------------------------------------------------|
| `zipped_outputs`      | yes      | `Array[File]`| none                                                | Zipped `nomadic` outputs (e.g. `Nomadic.wdl`'s `zipped_output_file`) to summarize. |
| `samples_to_include`  | yes      | `File`       | none                                                | GCS path to a one-column CSV with header `sample_id`. Used as `--metadata_csv`.   |
| `summary_name`        | yes      | `String`     | none                                                | Used as `--summary_name` and in the GCS output path.                              |
| `output_bucket_name`  | yes      | `String`     | none                                                | Bucket root for final outputs. Accepts with or without `gs://`.                   |
| `billing_project`     | yes      | `String`     | none                                                | Terra billing project for the `sample` table upload.                              |
| `workspace_name`      | yes      | `String`     | none                                                | Terra workspace name for the `sample` table upload.                               |
| `memory_gb`           | no       | `Int`        | `4`                                                 | Task runtime memory in GB (for `Summarize`).                                      |
| `disk_gb`             | no       | `Int`        | `100`                                               | Task runtime local disk size in GB (for `Summarize`).                             |
| `docker_name`         | no       | `String`     | `us.gcr.io/broad-gotc-prod/nomadic:latest`         | Docker image used to run `nomadic summarize` and the Terra upload script.          |

## Outputs

| output name          | required | type     | default               | notes                                                                                     |
|-----------------------|----------|----------|------------------------|--------------------------------------------------------------------------------------------|
| `zipped_output_file`  | yes      | `String` | generated at runtime   | GCS path to the zipped summary output.                                                    |
| `unzipped_output_dir` | yes      | `String` | generated at runtime   | GCS path to the unzipped summary output directory (same folder as `zipped_output_file`).   |
| `change_tsv_path`     | yes      | `String` | generated at runtime   | GCS path to the combined per-sample `aa_changes` TSV (this is a plain file now, not a Terra table). |
