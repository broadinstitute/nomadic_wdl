# Nomadic WDL

## Overview

`Nomadic.wdl` runs a single `Nomadic` workflow that prepares input data, runs `nomadic process`, and copies results to GCS.

High-level behavior:

- Chooses `reference_name`, `caller`, and `region_bed` from `organism` presets when `organism` is `pfalciparum` or `agambiae`.
- Accepts either `minknow_dir` or `fastq_dir` input data.
  - If `minknow_dir` is provided, it is used.
  - Else if `fastq_dir` is provided, it is used.
  - Else defaults to `gs://{bucket}/minknow/{experiment_name}`.
- Defaults `metadata_file` to `gs://{bucket}/metadata/{experiment_name}.csv` if not provided.
- Writes outputs under:
  - `gs://{bucket}/output/{run_name}/{experiment_name}/{YYYY_MM_DD_HH_MM}/`
- Optionally creates and uploads `outputs.zip`.

## Inputs

| input name               | required    | type       | default                                                             | notes                                                                                                          |
|--------------------------|-------------|------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| `organism`               | no          | `String?`  | none                                                                | Optional preset selector. Recognized values: `pfalciparum`, `agambiae`.                                        |
| `fastq_dir`              | no          | `String?`  | none                                                                | GCS path to FASTQ directory. Used when `minknow_dir` is not provided.                                          |
| `minknow_dir`            | no          | `String?`  | `gs://{bucket}/minknow/{experiment_name}` (if `fastq_dir` is unset) | GCS path to MinKNOW directory. Takes precedence over `fastq_dir` when both are set.                            |
| `metadata_file`          | no          | `File?`    | `gs://{bucket}/metadata/{experiment_name}.csv`                      | Used as `--metadata_csv`; default applies when omitted.                                                        |
| `experiment_name`        | yes         | `String`   | none                                                                | Experiment name passed to `nomadic process` and used in output path.                                           |
| `run_name`               | yes         | `String`   | none                                                                | Groups outputs under `output/{run_name}/...`.                                                                  |
| `reference_name`         | conditional | `String?`  | preset from `organism` or none                                      | Optional if `organism` is a recognized preset; otherwise required.                                             |
| `caller`                 | conditional | `String?`  | preset from `organism` or none                                      | Optional if `organism` is a recognized preset; otherwise required.                                             |
| `region_bed`             | conditional | `File?`    | preset from `organism` or none                                      | Optional if `organism` is a recognized preset; otherwise required.                                             |
| `bucket_name`            | yes         | `String`   | none                                                                | Bucket root for defaults and final outputs. Accepts with or without `gs://`.                                   |
| `preserve_barcode_files` | yes         | `Boolean`  | none                                                                | `true`: exclude only `.incremental`; `false`: exclude `.incremental` and `barcode` in copied/archived outputs. |
| `zip_outputs`            | no          | `Boolean`  | `true`                                                              | If `true`, creates and uploads `outputs.zip`.                                                                  |
| `memory_gb`              | no          | `Int`      | `4`                                                                 | Task runtime memory in GB.                                                                                     |
| `disk_gb`                | no          | `Int`      | `100`                                                               | Task runtime local disk size in GB.                                                                            |

## Outputs

| output name          | required   | type     | default                               | notes                                                                                     |
|----------------------|------------|----------|---------------------------------------|-------------------------------------------------------------------------------------------|
| `output_dir_path`    | yes        | `String` | generated at runtime                  | Final GCS output directory path.                                                          |
| `zipped_output_file` | yes        | `String` | empty string when `zip_outputs=false` | GCS path to `outputs.zip` when `zip_outputs=true`; empty string when `zip_outputs=false`. |



