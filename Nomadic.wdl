version 1.0

workflow Nomadic {
    input {
        String fastq_dir
        File metadata_file
        String experiment_name
        String reference_name
        String? caller
        File region_bed
        Int memory_gb = 10
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
            memory_gb = memory_gb,
            disk_gb = disk_gb,
            disk_type = disk_type
    }

    output {
        File summary_read_mapping = RunNomadic.summary_read_mapping
        File summary_region_coverage = RunNomadic.summary_region_coverage
        File summary_variants = RunNomadic.summary_variants
    }
}

task RunNomadic {
    input {
        String fastq_dir
        File metadata_file
        String experiment_name
        String reference_name
        String? caller
        File region_bed
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
        gcloud alpha storage cp -r ~{fastq_dir}/* fastq_data/

        # Run nomadic process command
        echo "Time elapsed: $(timestamp) - Runing nomadic process for experiment ~{experiment_name}"
        nomadic process ~{experiment_name} \
            --metadata_csv ~{metadata_file} \
            --region_bed ~{region_bed} \
            --fastq_dir fastq_data \
            --reference_name ~{reference_name} \
            ~{"--caller " + caller} \
            --output results/~{experiment_name}

        echo "Time elapsed: $(timestamp) - Finding output summary files:"
        find ./results/~{experiment_name}/ -type f
    >>>

    runtime {
        docker: "us.gcr.io/broad-gotc-prod/nomadic:latest"
        memory: "~{memory_gb} GB"
        disks: "local-disk ~{disk_gb} ~{disk_type}"
    }

    output {
        File summary_read_mapping = "./results/~{experiment_name}/~{experiment_name}.summary.read_mapping.csv"
        File summary_region_coverage = "./results/~{experiment_name}/~{experiment_name}.summary.region_coverage.csv"
        File summary_variants = "./results/~{experiment_name}/~{experiment_name}.summary.variants.csv"
    }
}
