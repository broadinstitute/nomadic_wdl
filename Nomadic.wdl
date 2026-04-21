version 1.0

workflow Nomadic {
    input {
        String? organism
        String? fastq_dir
        # Input should be something like "gs://{bucket}/minknow/{experiment_name}" (trailing slash optional)
        String? minknow_dir
        File? metadata_file
        String experiment_name
        String run_name
        String? reference_name
        String? caller
        File? region_bed
        String bucket_name
        # TODO do we want to set a default true/false value here if one option is more common?
        Boolean preserve_barcode_files
        Boolean zip_outputs = false
        Int memory_gb = 4
        Int disk_gb = 20
    }

    # Determine reference_name based on organism or use provided value
    String final_reference_name = if defined(organism) then (
        if select_first([organism]) == "pfalciparum" then "Pf3D7"
        else if select_first([organism]) == "agambiae" then "AgPEST"
        else select_first([reference_name])
    ) else select_first([reference_name])

    # Determine caller based on organism or use provided value
    String final_caller = if defined(organism) then (
        if select_first([organism]) == "pfalciparum" then "delve"
        else if select_first([organism]) == "agambiae" then "bcftools"
        else select_first([caller])
    ) else select_first([caller])

    # Determine region_bed based on organism or use provided value
    File final_region_bed = if defined(organism) then (
        # TODO: Update paths to point to the correct bucket and files once they are finalized
        if select_first([organism]) == "pfalciparum" then "gs://fc-e51e0216-60e9-4434-91df-3044195c8816/beds/nomadsMVP.amplicons.bed"
        else if select_first([organism]) == "agambiae" then "gs://fc-e51e0216-60e9-4434-91df-3044195c8816/beds/nomadsIR.amplicons.bed"
        else select_first([region_bed])
    ) else select_first([region_bed])

    # Normalize bucket_name by removing gs:// and any trailing slash.
    String normalized_bucket_name = sub(sub(bucket_name, "^gs://", ""), "/$", "")

    # Use provided fastq_dir when present; otherwise keep it empty.
    String final_fastq_dir = if defined(fastq_dir) then (select_first([fastq_dir])) else ""

    # Use provided minknow_dir; if absent and fastq_dir is absent, derive a default minknow path.
    String final_minknow_dir = if defined(minknow_dir) then (
        select_first([minknow_dir])
    ) else if defined(fastq_dir) then "" else (
        "gs://" + normalized_bucket_name + "/minknow/" + experiment_name
    )

    # Use provided metadata_file or default to gs://{normalized_bucket_name}/metadata/{experiment_name}.csv.
    File final_metadata_file = if defined(metadata_file) then (
        select_first([metadata_file])
    ) else "gs://" + normalized_bucket_name + "/metadata/" + experiment_name + ".csv"

    call RunNomadic {
        input:
            fastq_dir = final_fastq_dir,
            minknow_dir = final_minknow_dir,
            metadata_file = final_metadata_file,
            experiment_name = experiment_name,
            run_name = run_name,
            reference_name = final_reference_name,
            caller = final_caller,
            region_bed = final_region_bed,
            bucket_name = normalized_bucket_name,
            preserve_barcode_files = preserve_barcode_files,
            zip_outputs = zip_outputs,
            memory_gb = memory_gb,
            disk_gb = disk_gb
    }

    output {
        String output_dir_path = RunNomadic.output_dir_path
        String zipped_output_file = RunNomadic.zipped_output_file
    }
}

task RunNomadic {
    input {
        String fastq_dir
        String minknow_dir
        File metadata_file
        String experiment_name
        String run_name
        String reference_name
        String caller
        File region_bed
        String bucket_name
        Boolean preserve_barcode_files
        Boolean zip_outputs
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

        # Normalize fastq_dir (remove trailing slash if present)
        FASTQ_DIR="~{fastq_dir}"
        FASTQ_DIR="${FASTQ_DIR%/}"

        # Normalize minknow_dir (remove trailing slash if present)
        MINKNOW_DIR="~{minknow_dir}"
        MINKNOW_DIR="${MINKNOW_DIR%/}"

        declare -a INPUT_ARGS
        if [[ -n "$MINKNOW_DIR" ]]; then
            echo "Time elapsed: $(timestamp) - Copying MinKNOW data from $MINKNOW_DIR to minknow_data/"
            mkdir -p minknow_data
            gsutil -q -m cp -r "$MINKNOW_DIR"/* minknow_data/
            INPUT_ARGS=(--minknow_dir minknow_data)
        elif [[ -n "$FASTQ_DIR" ]]; then
            echo "Time elapsed: $(timestamp) - Copying FASTQ data from $FASTQ_DIR to fastq_data/"
            mkdir -p fastq_data
            gsutil -q -m cp -r "$FASTQ_DIR"/* fastq_data/
            INPUT_ARGS=(--fastq_dir fastq_data)
        else
            echo "Time elapsed: $(timestamp) - ERROR: neither minknow_dir nor fastq_dir was provided" >&2
            exit 1
        fi

        # Copy the reference
        echo "Time elapsed: $(timestamp) - Copying reference ~{reference_name}"
        nomadic download --reference_name ~{reference_name}

        # Run nomadic process command
        echo "Time elapsed: $(timestamp) - Runing nomadic process for experiment ~{experiment_name}"
        nomadic process ~{experiment_name} \
            --metadata_csv ~{metadata_file} \
            --region_bed ~{region_bed} \
            "${INPUT_ARGS[@]}" \
            --reference_name ~{reference_name} \
            --caller ~{caller} \
            --output results/~{experiment_name}

        # Generate timestamped output path
        date_str=$(date +%Y_%m_%d_%H_%M)
        OUTPUT_DIR="gs://~{bucket_name}/output/~{run_name}/~{experiment_name}/${date_str}/"
        echo "${OUTPUT_DIR}" > output_dir_path.txt

        # Copy results to output path
        echo "Time elapsed: $(timestamp) - Copying results to ${OUTPUT_DIR}"

        if [ "~{preserve_barcode_files}" == "true" ]; then
            # Copy all outputs, excluding only .incremental subdirectories
            gsutil -m rsync -r -x '.*\.incremental/.*' ./results/~{experiment_name}/ "${OUTPUT_DIR}"
        else
            # Copy all outputs, excluding both .incremental and barcode subdirectories
            gsutil -m rsync -r -x '.*\.incremental/.*|.*/barcode/.*' ./results/~{experiment_name}/ "${OUTPUT_DIR}"
        fi

        echo "Time elapsed: $(timestamp) - Copy complete"

        if [ "~{zip_outputs}" == "true" ]; then
            echo "Time elapsed: $(timestamp) - Zipping outputs"
            if [ "~{preserve_barcode_files}" == "true" ]; then
                # Zip all outputs, excluding only .incremental subdirectories
                zip -r outputs.zip ./results/~{experiment_name}/ -x '*/.incremental/*'
            else
                # Zip all outputs, excluding both .incremental and barcode subdirectories
                zip -r outputs.zip ./results/~{experiment_name}/ -x '*/.incremental/*' -x '*/barcode/*'
            fi
            ZIP_PATH="${OUTPUT_DIR}outputs.zip"
            gsutil -q cp outputs.zip "${ZIP_PATH}"
            echo "${ZIP_PATH}" > zipped_output_file.txt
            echo "Time elapsed: $(timestamp) - Zip complete"
        else
            echo "" > zipped_output_file.txt
        fi
    >>>

    runtime {
        docker: "us.gcr.io/broad-gotc-prod/nomadic:latest"
        memory: "~{memory_gb} GB"
        disks: "local-disk ~{disk_gb} HDD"
    }

    output {
        String output_dir_path = read_string("output_dir_path.txt")
        String zipped_output_file = read_string("zipped_output_file.txt")
    }
}
