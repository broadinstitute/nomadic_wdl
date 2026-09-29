"""
Combine multiple `nomadic summarize` aa_changes CSVs into one file and upload the
result to a Terra workspace as a data table.

Requires `pyops-service-toolkit` (module name `ops_utils`) to be installed, e.g.:
    pip install git+https://github.com/broadinstitute/pyops-service-toolkit.git
"""

import argparse
import logging
import os
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

# Terra data tables require the entity id column to be named "entity:<table_name>_id".
TABLE_NAME = "changes"
ENTITY_ID_COLUMN = f"entity:{TABLE_NAME}_id"

COMBINED_TSV_PATH = "combined_aa_changes.tsv"


def get_args() -> Namespace:
    parser = argparse.ArgumentParser(
        description="Combine nomadic aa_changes CSVs and upload as a Terra data table."
    )
    parser.add_argument("--change_files", "-c", nargs="+", required=True, help="Paths to aa_changes CSV files to combine.")
    parser.add_argument("--billing_project", "-b", required=True, help="Terra billing project.")
    parser.add_argument("--workspace_name", "-w", required=True, help="Terra workspace name.")
    return parser.parse_args()


def combine_change_files(change_files: list[str]) -> list[dict]:
    combined_rows = []
    for change_file in change_files:
        logging.info(f"Reading {change_file}")
        rows = Csv(file_path=change_file, delimiter=",").create_list_of_dicts_from_tsv(
            expected_headers=EXPECTED_HEADERS
        )
        for row in rows:
            row[ENTITY_ID_COLUMN] = f"{row['sample_id']}_{row['gene']}_{row['aa_change']}"
        combined_rows.extend(rows)
    return combined_rows


if __name__ == "__main__":
    args = get_args()

    combined_rows = combine_change_files(args.change_files)
    logging.info(f"Combined {len(combined_rows)} rows from {len(args.change_files)} file(s)")

    combined_tsv = Csv(file_path=COMBINED_TSV_PATH).create_tsv_from_list_of_dicts(
        combined_rows, header_list=[ENTITY_ID_COLUMN] + EXPECTED_HEADERS
    )

    token = Token()
    request_util = RunRequest(token=token)
    terra_workspace = TerraWorkspace(
        billing_project=args.billing_project,
        workspace_name=args.workspace_name,
        request_util=request_util,
    )
    logging.info(
        f"Uploading {combined_tsv} to Terra table '{TABLE_NAME}' "
        f"in {args.billing_project}/{args.workspace_name}"
    )
    terra_workspace.upload_metadata_to_workspace_table(entities_tsv=combined_tsv)
    logging.info("Done")
