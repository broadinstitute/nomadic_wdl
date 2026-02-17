version 1.0

workflow Nomadic {
    input {
        String? organism
        String fastq_dir
        File metadata_file
        String experiment_name
        String? reference_name
        String? caller
        File? region_bed
        String bucket_name
        # TODO do we want to set a default true/false value here if one option is more common?
        Boolean preserve_barcode_files
        Int memory_gb = 16
        Int disk_gb = 200
        String disk_type = "HDD"
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

    call RunNomadic {
        input:
            fastq_dir = fastq_dir,
            metadata_file = metadata_file,
            experiment_name = experiment_name,
            reference_name = final_reference_name,
            caller = final_caller,
            region_bed = final_region_bed,
            bucket_name = bucket_name,
            preserve_barcode_files = preserve_barcode_files,
            memory_gb = memory_gb,
            disk_gb = disk_gb,
            disk_type = disk_type
    }

    output {
        String output_path = RunNomadic.output_path
    }
}

task RunNomadic {
    input {
        String fastq_dir
        File metadata_file
        String experiment_name
        String reference_name
        String caller
        File region_bed
        String bucket_name
        Boolean preserve_barcode_files
        Int memory_gb
        Int disk_gb
        String disk_type
    }

    command <<<
        set -euo pipefail

        START_TIME=$(date +%s)
        timestamp() {
            local now=$(date +%s)
            local elapsed=$((now - START_TIME))
            printf '%02d:%02d:%02d' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
        }

        # Normalize bucket name (remove gs:// prefix and trailing slash if present)
        BUCKET_NAME="~{bucket_name}"
        BUCKET_NAME="${BUCKET_NAME#gs://}"
        BUCKET_NAME="${BUCKET_NAME%/}"

        # Copy the reference
        echo "Time elapsed: $(timestamp) - Copying reference ~{reference_name}"
        nomadic download --reference_name ~{reference_name}

        # Copy the fastq directory from cloud storage
        echo "Time elapsed: $(timestamp) - Copying data from ~{fastq_dir} to fastq_data/"
        mkdir -p fastq_data
        gsutil -q -m cp -r ~{fastq_dir}/* fastq_data/

        # Run nomadic process command
        echo "Time elapsed: $(timestamp) - Runing nomadic process for experiment ~{experiment_name}"
        nomadic process ~{experiment_name} \
            --metadata_csv ~{metadata_file} \
            --region_bed ~{region_bed} \
            --fastq_dir fastq_data \
            --reference_name ~{reference_name} \
            --caller ~{caller} \
            --output results/~{experiment_name}

        # Generate timestamped output path
        timestamp_for_path=$(date +%Y_%m_%d_%H_%M)
        OUTPUT_PATH="gs://${BUCKET_NAME}/~{experiment_name}/run_${timestamp_for_path}/"
        echo "${OUTPUT_PATH}" > output_path.txt

        # Copy results to output path
        echo "Time elapsed: $(timestamp) - Copying results to ${OUTPUT_PATH}"

        if [ "~{preserve_barcode_files}" == "true" ]; then
            # Copy all outputs, excluding only .incremental subdirectories
            gsutil -m rsync -r -x '.*\.incremental/.*' ./results/~{experiment_name}/ "${OUTPUT_PATH}"
        else
            # Copy all outputs, excluding both .incremental and barcode subdirectories
            gsutil -m rsync -r -x '.*\.incremental/.*|.*/barcode/.*' ./results/~{experiment_name}/ "${OUTPUT_PATH}"
        fi

        echo "Time elapsed: $(timestamp) - Copy complete"
    >>>

    runtime {
        docker: "us.gcr.io/broad-gotc-prod/nomadic:latest"
        memory: "~{memory_gb} GB"
        disks: "local-disk ~{disk_gb} ~{disk_type}"
    }

    output {
        String output_path = read_string("output_path.txt")
    }
}
