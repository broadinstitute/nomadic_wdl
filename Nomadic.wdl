version 1.0

workflow Nomadic {
    input {
        String cloud_directory
        File? metadata_file
        String experiment_name
        Int memory_gb = 10
        Int disk = 200
        String machine_type = "HDD"
    }

    call RunNomadic {
        input:
            cloud_directory = cloud_directory,
            metadata_file = metadata_file,
            experiment_name = experiment_name,
            memory_gb = memory_gb,
            disk = disk,
            machine_type = machine_type
    }

    # TODO: Define outputs once we know the location of the summary files
    #output {
    #
    #}
}

task RunNomadic {
    input {
        String cloud_directory
        File? metadata_file
        String experiment_name
        Int memory_gb
        Int disk
        String machine_type
    }

    command <<<
        set -euo pipefail

        START_TIME=$(date +%s)
        timestamp() {
            local now=$(date +%s)
            local elapsed=$((now - START_TIME))
            printf '%02d:%02d:%02d' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
        }


        # Copy the input directory from cloud storage
        echo "Time elapsed: $(timestamp) - Copying data from ~{cloud_directory} to minknow_data/"
        mkdir -p minknow_data
        gsutil -m cp -r ~{cloud_directory}/* minknow_data/

        # Run nomadic process command
        echo "Time elapsed: $(timestamp) - Runing nomadic process for experiment ~{experiment_name}"
        nomadic process ~{experiment_name} \
            ~{"-m " + metadata_file} \
            -k "minknow_data"

        echo "Time elapsed: $(timestamp) - Finding output summary files:"
        find . -type f -name "*summary.read_mapping.csv"
        find . -type f -name "*summary.region_coverage.csv"
        find . -type f -name "*summary.variants.csv"
    >>>

    runtime {
        docker: "us.gcr.io/broad-gotc-prod/nomadic:latest"
        memory: "~{memory_gb} GB"
        disks: "local-disk ~{disk} ~{machine_type}"
    }

    # TODO: Define outputs once we know the location of the summary files
    #output {
    #    # Add your output files here
    #}
}
