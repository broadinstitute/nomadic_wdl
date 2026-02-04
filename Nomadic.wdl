version 1.0

workflow Nomadic {
    input {
        String fastq_dir
        File metadata_file
        String experiment_name
        String reference_name
        String caller
        File region_bed
        String bucket_name
        # TODO do we want to set a default true/false value here if one option is more common?
        Boolean preserve_barcode_files
        Int memory_gb = 16
        Int disk_gb = 200
        String disk_type = "HDD"
    }

    call RunNomadic {
        input:
            fastq_dir = fastq_dir,
            metadata_file = metadata_file,
            experiment_name = experiment_name,
            reference_name = reference_name,
            caller = caller,
            region_bed = region_bed,
            bucket_name = bucket_name,
            preserve_barcode_files = preserve_barcode_files,
            memory_gb = memory_gb,
            disk_gb = disk_gb,
            disk_type = disk_type
    }

    output {
        String output_path = RunNomadic.output_path
        String summary_variants = output_path + "summary.variants.csv"
        String metadata_lowcomplexity_mask_bed = output_path + "metadata/nomadsMVP.amplicons.lowcomplexity_mask.bed"
        String metadata_settings_json = output_path + "metadata/settings.json"
        String metadata_amplicons_bed = output_path + "metadata/nomadsMVP.amplicons.bed"
        String metadata_samples_csv = output_path + "metadata/samples.csv"
        String summary_fastqs_processed = output_path + "summary.fastqs_processed.csv"
        String summary_depth_profiles = output_path + "summary.depth_profiles.csv"
        String summary_region_coverage = output_path + "summary.region_coverage.csv"
        String summary_read_mapping = output_path + "summary.read_mapping.csv"
        String vcf_summary_variants = output_path + "vcfs/summary.variants.vcf.gz"
        String vcf_summary_variants_filtered = output_path + "vcfs/summary.variants.filtered.annotated.vcf.gz"
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
        OUTPUT_PATH="gs://~{bucket_name}/~{experiment_name}/run_${timestamp_for_path}/"
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
