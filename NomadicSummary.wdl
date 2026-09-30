version 1.0

workflow NomadicSummary {
    input {
        Array[File] zipped_outputs
        # One-column CSV with header `sample_id`, listing samples to include. GCS path.
        File samples_to_include
        String summary_name
        String output_bucket_name
        String billing_project
        String workspace_name
        Int memory_gb = 4
        Int disk_gb = 100
        String docker_name = "us.gcr.io/broad-gotc-prod/nomadic:latest"
    }

    # Normalize output_bucket_name by removing gs:// and any trailing slash.
    String normalized_bucket_name = sub(sub(output_bucket_name, "^gs://", ""), "/$", "")

    call Summarize {
        input:
            zipped_outputs = zipped_outputs,
            samples_to_include = samples_to_include,
            summary_name = summary_name,
            bucket_name = normalized_bucket_name,
            memory_gb = memory_gb,
            disk_gb = disk_gb,
            docker_name = docker_name
    }

    call UploadChangesToTerra {
        input:
            aa_changes_files = Summarize.aa_changes_files,
            billing_project = billing_project,
            workspace_name = workspace_name,
            bucket_name = normalized_bucket_name,
            summary_name = summary_name,
            docker_name = docker_name
    }

    output {
        String zipped_output_file = Summarize.zipped_output_file
        String unzipped_output_dir = Summarize.unzipped_output_dir
        String change_tsv_path = UploadChangesToTerra.change_tsv_path
    }
}

task Summarize {
    input {
        Array[File] zipped_outputs
        File samples_to_include
        String summary_name
        String bucket_name
        String docker_name
        Int memory_gb
        Int disk_gb
    }

    command <<<
        set -euo pipefail

        START_TIME=$(date +%s)
        timestamp() {
            local now=$(date +%s)
            local elapsed=$((now - START_TIME))
            printf '%02d:%02d:%02d' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
        }

        # Unzip all nomadic zipped outputs into a single directory on the VM.
        UNZIP_DIR="unzipped_outputs"
        mkdir -p "$UNZIP_DIR"

        cat > zip_manifest.txt <<'EOF'
~{sep="\n" zipped_outputs}
EOF

        while IFS= read -r zip_path; do
            echo "Time elapsed: $(timestamp) - Unzipping $zip_path"
            unzip -q "$zip_path" -d "$UNZIP_DIR"
        done < zip_manifest.txt

        # Each nomadic zip extracts to results/<experiment_name>/ (see Nomadic.wdl);
        # collect those experiment directories to pass to `nomadic summarize`.
        mapfile -t EXPERIMENT_DIRS < <(find "$UNZIP_DIR/results" -mindepth 1 -maxdepth 1 -type d | sort)

        echo "Time elapsed: $(timestamp) - Running nomadic summarize for ~{summary_name}"
        nomadic summarize "${EXPERIMENT_DIRS[@]}" \
            --metadata_csv ~{samples_to_include} \
            --summary_name ~{summary_name} \
            --no-dashboard \
            --output-dir output/

        # `gcloud` (unlike `gsutil`) doesn't auto-detect the VM's attached service
        # account in a non-interactive container - it needs an explicit credential.
        # Fetch a short-lived access token from the GCE metadata server instead of
        # requiring `gcloud auth login` or a service account key file.
        export CLOUDSDK_AUTH_ACCESS_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
            | grep -Po '"access_token":"\K[^"]*')

        date_str=$(date +%Y_%m_%d_%H_%M)
        OUTPUT_DIR="gs://~{bucket_name}/summarize/output/~{summary_name}/${date_str}/"
        echo "${OUTPUT_DIR}" > unzipped_output_dir.txt

        # Copy the unzipped summary output to GCS
        echo "Time elapsed: $(timestamp) - Copying unzipped output to ${OUTPUT_DIR}"
        gcloud storage rsync --recursive output/ "${OUTPUT_DIR}"

        # Zip up the summary output
        echo "Time elapsed: $(timestamp) - Zipping summary output"
        zip -q -r output.zip output/

        # Copy the zipped output to GCS
        ZIP_PATH="${OUTPUT_DIR}output.zip"
        echo "Time elapsed: $(timestamp) - Copying zipped output to ${ZIP_PATH}"
        gcloud storage cp output.zip "${ZIP_PATH}"
        echo "${ZIP_PATH}" > zipped_output_file.txt

        echo "Time elapsed: $(timestamp) - Done"
    >>>

    runtime {
        docker: docker_name
        memory: "~{memory_gb} GB"
        disks: "local-disk ~{disk_gb} HDD"
    }

    output {
        String zipped_output_file = read_string("zipped_output_file.txt")
        String unzipped_output_dir = read_string("unzipped_output_dir.txt")
        # `nomadic summarize` writes the per-sample variant calls to
        # <output-dir>/variants/aa_changes.csv (plus one aa_changes.<set>.csv per
        # configured amplicon set) - this is the same glob nomadic itself uses
        # internally (see summarize/main.py). This must NOT also match the
        # separate, aggregated prevalence.aa_changes*.csv files nomadic writes to
        # the same directory - those have a different (non-per-sample) schema, and
        # the "aa_changes*.csv" pattern below only matches names starting with
        # "aa_changes", so it correctly excludes them.
        Array[File] aa_changes_files = glob("output/variants/aa_changes*.csv")
    }
}

task UploadChangesToTerra {
    input {
        Array[File] aa_changes_files
        String billing_project
        String workspace_name
        String bucket_name
        String summary_name
        String docker_name
    }

    command <<<
        set -euo pipefail

        date_str=$(date +%Y_%m_%d_%H_%M)

        # ops_utils (pyops-service-toolkit) lives in its own conda env in the image,
        # separate from nomadic's env - see Dockerfile for why. This combines the
        # per-sample aa_changes files into one TSV (written locally as
        # combined_aa_changes.tsv) and uploads a sample-centric "sample" table
        # (plus a dated copy) to Terra; it no longer uploads the per-change data
        # itself as a Terra table.
        /opt/conda/envs/terra_upload/bin/python /usr/local/bin/combine_change_files_to_terra.py \
            --change_files ~{sep=" " aa_changes_files} \
            --billing_project ~{billing_project} \
            --workspace_name ~{workspace_name} \
            --run_date_str "${date_str}"

        # `gcloud` (unlike `gsutil`) doesn't auto-detect the VM's attached service
        # account in a non-interactive container - it needs an explicit credential.
        # Fetch a short-lived access token from the GCE metadata server instead of
        # requiring `gcloud auth login` or a service account key file.
        export CLOUDSDK_AUTH_ACCESS_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
            | grep -Po '"access_token":"\K[^"]*')

        CHANGE_TSV_PATH="gs://~{bucket_name}/summarize/output/~{summary_name}/${date_str}/change.tsv"
        gcloud storage cp combined_aa_changes.tsv "${CHANGE_TSV_PATH}"
        echo "${CHANGE_TSV_PATH}" > change_tsv_path.txt
    >>>

    runtime {
        docker: docker_name
        memory: "4 GB"
        disks: "local-disk 20 HDD"
    }

    output {
        String change_tsv_path = read_string("change_tsv_path.txt")
    }
}
