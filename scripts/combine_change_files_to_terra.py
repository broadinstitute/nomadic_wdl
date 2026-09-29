"""
Combine multiple `nomadic summarize` aa_changes CSVs into one file and upload the
result to a Terra workspace as a data table.

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

# upload_metadata_with_batch_upsert requires the id column to be named
# "<table_name>_id" exactly.
TABLE_NAME = "changes"
ID_COLUMN = f"{TABLE_NAME}_id"


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
            row[ID_COLUMN] = f"{row['sample_id']}_{row['gene']}_{row['aa_change']}"
        combined_rows.extend(rows)
    return combined_rows


if __name__ == "__main__":
    args = get_args()

    combined_rows = combine_change_files(args.change_files)
    logging.info(f"Combined {len(combined_rows)} rows from {len(args.change_files)} file(s)")

    table_data = {
        TABLE_NAME: {
            "table_id_column": ID_COLUMN,
            "row_data": combined_rows,
        }
    }

    token = Token()
    request_util = RunRequest(token=token)
    terra_workspace = TerraWorkspace(
        billing_project=args.billing_project,
        workspace_name=args.workspace_name,
        request_util=request_util,
    )
    logging.info(
        f"Uploading {len(combined_rows)} rows to Terra table '{TABLE_NAME}' "
        f"in {args.billing_project}/{args.workspace_name}"
    )
    terra_workspace.upload_metadata_with_batch_upsert(table_data=table_data)
    logging.info("Done")
