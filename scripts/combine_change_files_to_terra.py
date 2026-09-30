"""
Combine multiple `nomadic summarize` aa_changes CSVs into:
- a single combined per-change TSV file (written locally; the WDL task uploads it
  to GCS and exposes the path as a task/workflow output)
- a sample-centric Terra data table ("sample"), pivoting each sample's amino acid
  calls into columns named aa_change_<gene>_<aa_change>, valued with aa_call.
  Also uploads a second, dated copy of that table (e.g. "sample_2026_09_30_14_22")
  so each run's sample table is preserved as its own browsable table.

Requires `pyops-service-toolkit` (module name `ops_utils`) to be installed, e.g.:
    pip install git+https://github.com/broadinstitute/pyops-service-toolkit.git
"""

import argparse
import logging
from argparse import Namespace

from ops_utils.csv_util import Csv
from ops_utils.request_util import RunRequest
from ops_utils.terra_util import TerraWorkspace
from ops_utils.token_util import Token

logging.basicConfig(format="%(levelname)s: %(asctime)s : %(message)s", level=logging.INFO)

# All change_files must have exactly this header (nomadic summarize's per-sample
# aa_changes*.csv format - NOT the aggregated prevalence.aa_changes*.csv format).
EXPECTED_HEADERS = [
    "sample_id",
    "expt_name",
    "barcode",
    "chrom",
    "amplicon",
    "gene",
    "aa_pos",
    "aa_change",
    "aa_call",
    "aa_dp",
    "aa_wsaf",
    "nt_change",
]

CHANGE_TSV_PATH = "combined_aa_changes.tsv"

# upload_metadata_with_batch_upsert requires the id column to be named
# "<table_name>_id" exactly (without force=True). sample_id already matches that
# for the base "sample" table; the dated copy uses force=True instead of a
# per-date id column name, since the underlying id is still just sample_id.
SAMPLE_TABLE_NAME = "sample"
SAMPLE_ID_COLUMN = "sample_id"


def get_args() -> Namespace:
    parser = argparse.ArgumentParser(
        description="Combine nomadic aa_changes CSVs into a per-change TSV and a sample-centric Terra table."
    )
    parser.add_argument("--change_files", "-c", nargs="+", required=True, help="Paths to aa_changes CSV files to combine.")
    parser.add_argument("--billing_project", "-b", required=True, help="Terra billing project.")
    parser.add_argument("--workspace_name", "-w", required=True, help="Terra workspace name.")
    parser.add_argument(
        "--run_date_str", required=True,
        help="Timestamp string (e.g. 2026_09_30_14_22) used to name the dated copy of the sample table."
    )
    return parser.parse_args()


def combine_change_files(change_files: list[str]) -> list[dict]:
    combined_rows = []
    for change_file in change_files:
        logging.info(f"Reading {change_file}")
        rows = Csv(file_path=change_file, delimiter=",").create_list_of_dicts_from_tsv(
            expected_headers=EXPECTED_HEADERS
        )
        combined_rows.extend(rows)
    return combined_rows


def build_sample_centric_rows(combined_rows: list[dict]) -> tuple[list[dict], list[str]]:
    """
    Pivot per-change rows into one row per sample_id. Each unique (gene, aa_change)
    pair becomes its own column named aa_change_<gene>_<aa_change>, valued with
    that sample's aa_call for it. Samples missing a given change simply don't have
    that key set, so most rows will be missing most change columns.

    Returns (sample_rows, sorted list of all aa_change_<gene>_<aa_change> columns seen).
    """
    samples: dict[str, dict] = {}
    change_columns: set[str] = set()

    for row in combined_rows:
        sample_id = row["sample_id"]
        change_column = f"aa_change_{row['gene']}_{row['aa_change']}"
        change_columns.add(change_column)

        if sample_id not in samples:
            samples[sample_id] = {SAMPLE_ID_COLUMN: sample_id}
        samples[sample_id][change_column] = row["aa_call"]

    return list(samples.values()), sorted(change_columns)


if __name__ == "__main__":
    args = get_args()

    combined_rows = combine_change_files(args.change_files)
    logging.info(f"Combined {len(combined_rows)} rows from {len(args.change_files)} file(s)")

    Csv(file_path=CHANGE_TSV_PATH).create_tsv_from_list_of_dicts(
        combined_rows, header_list=EXPECTED_HEADERS
    )
    logging.info(f"Wrote combined per-change data to {CHANGE_TSV_PATH}")

    sample_rows, change_columns = build_sample_centric_rows(combined_rows)
    logging.info(
        f"Pivoted into {len(sample_rows)} sample rows across {len(change_columns)} amino acid change columns"
    )
    shown_columns = change_columns

    dated_table_name = f"{SAMPLE_TABLE_NAME}_{args.run_date_str}"

    token = Token()
    request_util = RunRequest(token=token)
    terra_workspace = TerraWorkspace(
        billing_project=args.billing_project,
        workspace_name=args.workspace_name,
        request_util=request_util,
    )

    # Delete the existing "sample" table (if any) so it always reflects only this
    # run's data - unlike upsert, which only adds/updates rows and would otherwise
    # leave stale rows around for samples not present in this run.
    existing_tables = terra_workspace.get_workspace_entity_info(use_cache=False).json()
    if SAMPLE_TABLE_NAME in existing_tables:
        logging.info(f"Deleting existing '{SAMPLE_TABLE_NAME}' table before re-upload")
        terra_workspace.delete_entity_table(SAMPLE_TABLE_NAME)

    # Column order must be set before each table has any data - setting it after
    # requires clearing browser local storage to take effect. See
    # https://support.terra.bio/hc/en-us/articles/7074648223515
    for table_name in (SAMPLE_TABLE_NAME, dated_table_name):
        terra_workspace.set_table_column_order(
            column_order={table_name: {"shown": shown_columns, "hidden": []}}
        )

    logging.info(f"Uploading {len(sample_rows)} sample rows to Terra table '{SAMPLE_TABLE_NAME}'")
    terra_workspace.upload_metadata_with_batch_upsert(
        table_data={
            SAMPLE_TABLE_NAME: {
                "table_id_column": SAMPLE_ID_COLUMN,
                "row_data": sample_rows,
            }
        }
    )

    logging.info(f"Uploading {len(sample_rows)} sample rows to dated Terra table '{dated_table_name}'")
    terra_workspace.upload_metadata_with_batch_upsert(
        table_data={
            dated_table_name: {
                "table_id_column": SAMPLE_ID_COLUMN,
                "row_data": sample_rows,
            }
        },
        force=True,
    )

    logging.info("Upload complete.")
