version 1.0

workflow TestWdl {
    input {
        String output_dir
        Int memory_gb = 16
        Int disk_gb = 200
        String disk_type = "HDD"
    }

    call CreateDashboard {
        input:
            output_dir = output_dir,
            memory_gb = memory_gb,
            disk_gb = disk_gb,
            disk_type = disk_type
    }

    output {
        String output_path = CreateDashboard.output_path
    }
}

task CreateDashboard {
    input {
        String output_dir
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

        # Copy the output directory from cloud storage
        echo "Time elapsed: $(timestamp) - Copying data from ~{output_dir} to output/"
        mkdir -p output
        gsutil -q -m cp -r ~{output_dir}/* output/

        # Run nomadic process command
        echo "Time elapsed: $(timestamp) - Runing nomadic dashboard"
        nomadic dashboard output

        # Find all files
        find . -type f

        echo "Time elapsed: $(timestamp) - All Complete"
    >>>

    runtime {
        docker: "us.gcr.io/broad-gotc-prod/nomadic:latest"
        memory: "~{memory_gb} GB"
        disks: "local-disk ~{disk_gb} ~{disk_type}"
    }

    output {
            String output_path = "~{output_dir}"
    }
}
