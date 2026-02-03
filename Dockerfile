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
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
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
# - Let nomadic pull in its own samtools dependency
RUN conda config --system --remove-key channels || true \
 && conda config --system --add channels conda-forge \
 && conda config --system --add channels bioconda \
 && conda config --system --add channels defaults \
 && mamba create -n "${CONDA_ENV}" -y \
        python=3.11 \
        bioconda::nomadic \
 && conda clean -a -f

# Make the env the default.
ENV PATH=/opt/conda/envs/${CONDA_ENV}/bin:/opt/conda/bin:$PATH

# Sanity checks at build time.
RUN nomadic --help >/dev/null \
 && samtools --version | head -n 2 \
 && gsutil version -l | head -n 20 \
 && python --version

WORKDIR /work
CMD ["bash"]
