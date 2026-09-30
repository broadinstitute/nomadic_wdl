# syntax=docker/dockerfile:1

# Bioconda packages (like nomadic) have much better availability on linux/amd64.
# On Apple Silicon, build with: docker build --platform=linux/amd64 ...
FROM condaforge/miniforge3:24.11.3-0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Keep conda non-interactive and predictable.
ENV DEBIAN_FRONTEND=noninteractive \
    CONDA_ALWAYS_YES=true \
    CONDA_AUTO_UPDATE_CONDA=false \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Use a named environment (instead of base) to reduce solver conflicts.
ARG CONDA_ENV=nomadic

# Install gsutil via Google Cloud SDK (apt), not conda.
# This avoids python_abi pinning conflicts in conda, and is the most widely supported install path.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg zip unzip git \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends google-cloud-cli \
 && rm -rf /var/lib/apt/lists/*


# Configure channels and install nomadic from bioconda.
# Notes:
# - Use mamba for faster/better dependency solving
# - Pin python=3.11 to avoid dependency incompatibilities with newer Python versions
# - Explicitly install gsl (GNU Scientific Library) required by bcftools
# - Let nomadic pull in its own samtools dependency
RUN conda config --system --remove-key channels || true \
 && conda config --system --add channels conda-forge \
 && conda config --system --add channels bioconda \
 && conda config --system --add channels defaults \
 && mamba create -n "${CONDA_ENV}" -y \
        python=3.11 \
        bioconda::nomadic=0.9.0 \
        bioconda::bcftools \
        conda-forge::gsl \
 && conda clean -a -f

# Make the env the default.
ENV PATH=/opt/conda/envs/${CONDA_ENV}/bin:/opt/conda/bin:$PATH

# Install pyops-service-toolkit (module name `ops_utils`) for the
# combine_change_files_to_terra.py script's CSV handling and Terra upload, in its
# own conda env - NOT the nomadic env. pyops-service-toolkit's dependency chain
# (pandas, pydantic, etc. via pip) pulls in versions that conflict with nomadic's
# own conda-installed pandas/dash/pydantic; pip wheel pandas is also built against
# a newer glibc/libstdc++ than this image provides, which breaks nomadic's own
# pandas import (ImportError: GLIBCXX_3.4.29 not found) if installed into the same
# env. Keeping it fully separate avoids both problems.
RUN mamba create -n terra_upload -y python=3.11 pip \
 && conda clean -a -f
RUN /opt/conda/envs/terra_upload/bin/pip install \
    "git+https://github.com/broadinstitute/pyops-service-toolkit.git@v12.20.0#egg=pyops-service-toolkit"

# Add the script that combines nomadic's per-sample aa_changes CSVs and uploads
# them to a Terra data table. Run it with the terra_upload env's python, not the
# default `python` (which is nomadic's env and does not have ops_utils installed).
COPY scripts/combine_change_files_to_terra.py /usr/local/bin/combine_change_files_to_terra.py

# Fix nomadic's data directory to a known, absolute path rather than relying on
# $HOME (platformdirs' user_data_dir honors $XDG_DATA_HOME when set). This is where
# `nomadic download` would normally place reference genomes; we bake them in below
# instead, so the WDL never has to call `nomadic download` at runtime.
ENV XDG_DATA_HOME=/opt/xdg-data

# Bake in reference genomes from the repo, at the exact paths nomadic's
# download/references.py expects: <user_data_dir>/resources/<source>/<release>/<file>.
# AgPEST -> vectorbase/67. As of nomadic 0.9.0, Pf3D7 -> ensemblegenomes/63 (PlasmoDB
# can no longer be downloaded without auth, so nomadic switched Pf3D7 to Ensembl
# Genomes; see the "PlasmoDB can not be used anymore without auth" comment in
# nomadic's references.py). Adding more references later just means adding a
# references/<Name>/ folder in the repo plus a COPY line here.
COPY references/Pf3D7/ ${XDG_DATA_HOME}/nomadic/resources/ensemblegenomes/63/
COPY references/AgPEST/ ${XDG_DATA_HOME}/nomadic/resources/vectorbase/67/

# Sanity checks at build time.
# The reference fasta size check (>1MB) matters specifically because these files are
# stored in Git LFS: if the build context was checked out without `git lfs pull`, the
# path exists but only holds a ~130-byte LFS pointer stub, not the real genome. A plain
# `test -s` (non-empty) would pass on that stub and silently ship a broken image.
RUN nomadic --help >/dev/null \
 && nomadic summarize --help >/dev/null \
 && /opt/conda/envs/terra_upload/bin/python -c "import ops_utils" \
 && /opt/conda/envs/terra_upload/bin/python /usr/local/bin/combine_change_files_to_terra.py --help >/dev/null \
 && samtools --version | head -n 2 \
 && bcftools --version | head -n 2 \
 && gsutil version -l | head -n 20 \
 && zip -v | head -n 2 \
 && unzip -v | head -n 2 \
 && python --version \
 && for f in \
      "${XDG_DATA_HOME}/nomadic/resources/ensemblegenomes/63/Plasmodium_falciparum.GCA000002765v3.dna.toplevel.fasta" \
      "${XDG_DATA_HOME}/nomadic/resources/vectorbase/67/VectorBase-67_AgambiaePEST_Genome.fasta" \
    ; do \
      size=$(stat -c%s "$f"); \
      if [ "$size" -lt 1000000 ]; then \
        echo "ERROR: $f is only ${size} bytes - looks like an unfetched Git LFS pointer" \
             "file, not the real reference genome. Run 'git lfs pull' before building." >&2; \
        exit 1; \
      fi; \
    done

WORKDIR /work
CMD ["bash"]
