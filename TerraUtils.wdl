version 1.0

# Ported from broadinstitute/long-read-pipelines, branch
# jts_hmmibd_vcf_list_combine (wdl/tasks/Utility/TerraUtils.wdl), adapted to
# the self-contained nomadic_wdl style (no Structs.wdl / RuntimeAttr).

workflow GetTerraWorkspaceMetadata {
    input {
        String? namespace
        String? workspace
        String docker_name = "us.gcr.io/broad-dsp-lrma/lr-backup-workspace:0.0.1"
    }

    call GetWorkspaceMetadata {
        input:
            namespace = namespace,
            workspace = workspace,
            docker_name = docker_name
    }

    output {
        File          metadata_json         = GetWorkspaceMetadata.metadata_json
        File          attributes_json       = GetWorkspaceMetadata.attributes_json
        String        workspace_namespace   = GetWorkspaceMetadata.workspace_namespace
        String        workspace_name        = GetWorkspaceMetadata.workspace_name
        String        workspace_id          = GetWorkspaceMetadata.workspace_id
        String        bucket_name           = GetWorkspaceMetadata.bucket_name
        String        bucket                = GetWorkspaceMetadata.bucket
        String        google_project        = GetWorkspaceMetadata.google_project
        String        created_by            = GetWorkspaceMetadata.created_by
        String        created_date          = GetWorkspaceMetadata.created_date
        String        last_modified         = GetWorkspaceMetadata.last_modified
        Boolean       is_locked             = GetWorkspaceMetadata.is_locked
        String        access_level          = GetWorkspaceMetadata.access_level
        String        description           = GetWorkspaceMetadata.description
        Array[String] authorization_domains = GetWorkspaceMetadata.authorization_domains
    }
}

task GetWorkspaceMetadata {

    meta {
        description: "Fetch the FULL Terra metadata for the workspace this task is running in (fapi.get_workspace). The workspace is auto-detected -- WORKSPACE_NAMESPACE/WORKSPACE_NAME env vars (set in Terra runtimes), else the workspace whose Google project matches this VM's project (metadata server) via fapi.list_workspaces -- unless namespace/workspace are passed. Emits the raw JSON, the workspace attributes as their own JSON, and the commonly-used scalar fields as typed outputs."
        volatile: true
    }

    parameter_meta {
        namespace:   "Optional Terra billing project / namespace. Auto-detected when omitted."
        workspace:   "Optional workspace name. Auto-detected when omitted."
        docker_name: "Docker image to run in; must have python3 with the firecloud (FISS) package."
    }

    input {
        String? namespace
        String? workspace
        String docker_name = "us.gcr.io/broad-dsp-lrma/lr-backup-workspace:0.0.1"
    }

    command <<<
        set -euxo pipefail

        python3 <<CODE
        import os, sys, json, urllib.request
        import firecloud.api as fapi

        def gce_project():
            # This VM's Google project from the metadata server (no curl dependency).
            req = urllib.request.Request(
                "http://metadata.google.internal/computeMetadata/v1/project/project-id",
                headers={"Metadata-Flavor": "Google"},
            )
            try:
                return urllib.request.urlopen(req, timeout=5).read().decode().strip()
            except Exception as e:
                sys.stderr.write("WARNING: could not read Google project from metadata server: {}\n".format(e))
                return ""

        namespace = "~{default='' namespace}"
        workspace = "~{default='' workspace}"

        def resolve_workspace(namespace, workspace):
            # 1. Explicit inputs win.
            if namespace and workspace:
                return namespace, workspace
            # 2. Terra-injected environment variables (interactive runtimes).
            namespace = namespace or os.environ.get("WORKSPACE_NAMESPACE", "")
            workspace = workspace or os.environ.get("WORKSPACE_NAME", "")
            if namespace and workspace:
                return namespace, workspace
            # 3. Derive from this VM's Google project (one project per workspace in Terra).
            project = os.environ.get("GOOGLE_PROJECT", "") or gce_project()
            if not project:
                sys.stderr.write("ERROR: no namespace/workspace and no Google project; cannot auto-detect workspace.\n")
                sys.exit(1)
            resp = fapi.list_workspaces(fields="workspace.namespace,workspace.name,workspace.googleProject")
            if resp.status_code != 200:
                sys.stderr.write(f"ERROR: list_workspaces HTTP {resp.status_code}: {resp.text}\n")
                sys.exit(1)
            matches = sorted({
                (w["workspace"]["namespace"], w["workspace"]["name"])
                for w in resp.json()
                if w["workspace"].get("googleProject") == project
            })
            if len(matches) == 1:
                return matches[0]
            sys.stderr.write(
                f"ERROR: could not uniquely auto-detect the workspace for Google project '{project}' "
                f"(found {len(matches)} match(es)); pass namespace and workspace explicitly.\n"
            )
            sys.exit(1)

        namespace, workspace = resolve_workspace(namespace, workspace)

        resp = fapi.get_workspace(namespace, workspace)
        if resp.status_code != 200:
            sys.stderr.write(f"ERROR: get_workspace {namespace}/{workspace} HTTP {resp.status_code}: {resp.text}\n")
            sys.exit(1)
        full  = resp.json()
        ws    = full.get("workspace", {}) or {}
        attrs = ws.get("attributes", {}) or {}

        # Full payload + the custom attributes as their own files.
        with open("workspace_metadata.json", "w") as f:
            json.dump(full, f, indent=2, sort_keys=True)
        with open("workspace_attributes.json", "w") as f:
            json.dump(attrs, f, indent=2, sort_keys=True)

        # Commonly-used scalars -> individual files for typed WDL outputs.
        def w(path, val):
            with open(path, "w") as f:
                f.write("" if val is None else str(val))

        w("namespace.txt",      ws.get("namespace", ""))
        w("name.txt",           ws.get("name", ""))
        w("workspace_id.txt",   ws.get("workspaceId", ""))
        w("bucket_name.txt",    ws.get("bucketName", ""))
        w("bucket_uri.txt",     ("gs://" + ws["bucketName"]) if ws.get("bucketName") else "")
        w("google_project.txt", ws.get("googleProject", ""))
        w("created_by.txt",     ws.get("createdBy", ""))
        w("created_date.txt",   ws.get("createdDate", ""))
        w("last_modified.txt",  ws.get("lastModified", ""))
        w("is_locked.txt",      "true" if ws.get("isLocked") else "false")
        w("access_level.txt",   full.get("accessLevel", ""))
        w("description.txt",    attrs.get("description", ""))
        ad = [g.get("membersGroupName", "") for g in (ws.get("authorizationDomain", []) or [])]
        with open("auth_domains.txt", "w") as f:
            f.write("\n".join([x for x in ad if x]))

        print(f"Fetched metadata for {namespace}/{workspace} (bucket gs://{ws.get('bucketName','?')}).")
        CODE
    >>>

    output {
        File          metadata_json         = "workspace_metadata.json"   # full fapi.get_workspace payload
        File          attributes_json       = "workspace_attributes.json" # just workspace.attributes (custom key-values)
        String        workspace_namespace   = read_string("namespace.txt")
        String        workspace_name        = read_string("name.txt")
        String        workspace_id          = read_string("workspace_id.txt")
        String        bucket_name           = read_string("bucket_name.txt")
        String        bucket                = read_string("bucket_uri.txt")  # gs://<bucket_name>
        String        google_project        = read_string("google_project.txt")
        String        created_by            = read_string("created_by.txt")
        String        created_date          = read_string("created_date.txt")
        String        last_modified         = read_string("last_modified.txt")
        Boolean       is_locked             = read_boolean("is_locked.txt")
        String        access_level          = read_string("access_level.txt")
        String        description           = read_string("description.txt")
        Array[String] authorization_domains = read_lines("auth_domains.txt")
    }

    runtime {
        docker: docker_name
        memory: "2 GB"
        disks: "local-disk 10 HDD"
        preemptible: 2
        maxRetries: 1
    }
}
