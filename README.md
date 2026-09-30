# nomadic_wdl container

This repo includes a simple Docker image that contains:

- `conda` + `mamba` + `python`
- `gsutil` (via Google Cloud CLI)
- `nomadic` (installed from Bioconda)
- `samtools >=1.20` (automatically included as a nomadic dependency)
- Reference genomes baked in under `references/` (see below), so the WDL never
  needs to call `nomadic download` at runtime

## Prerequisite: Git LFS

The reference genome files under `references/` (FASTA, GFF, mask BED — some
hundreds of MB) are stored in [Git LFS](https://git-lfs.github.com), not as
regular git blobs, so they don't hit GitHub's 100MB file size limit. Before
cloning or building this repo, install and initialize `git-lfs`:

```sh
brew install git-lfs   # or your platform's package manager
git lfs install
```

If you clone/pull without `git-lfs` installed, `references/` will silently
contain tiny LFS pointer stub files instead of the real genomes. The
Dockerfile's build-time sanity checks will catch this (build fails with an
error telling you to run `git lfs pull`), but it's easiest to just have
`git-lfs` set up before you start. See `references/README.md` for details on
what's stored there and how to add more references.

## Build

### Apple Silicon (M1 and newer)

Bioconda’s `samtools/htslib` dependency chain for `nomadic` is much more reliable on `linux/amd64` than `linux/arm64`.
Build the image for `linux/amd64`:

```sh
docker build --platform=linux/amd64 -t nomadic:latest .
```

### Intel Linux / Intel macOS

```sh
docker build -t nomadic:latest .
```

## Smoke test

```sh
docker run --rm nomadic:latest nomadic --help
```

(If you built with `--platform=linux/amd64` on Apple Silicon, also run with that platform:)

```sh
docker run --rm --platform=linux/amd64 nomadic:latest nomadic --help
```

## Interactive shell

```sh
docker run -it --rm -v "$PWD":/work nomadic:latest
```

## Notes

- `nomadic` is installed with: `mamba create -n nomadic bioconda::nomadic`
  - **mamba** (not conda) is used for better dependency resolution of the samtools/htslib chain
  - Installed in a dedicated conda environment (not base) to avoid solver conflicts
- `gsutil` is provided by the Google Cloud CLI (`google-cloud-cli`) via apt
  - Installed separately from conda to avoid python_abi pinning conflicts
- `samtools >=1.20` is automatically pulled in as a dependency of nomadic

## Push to GCR

If you want to publish this image to:

`us.gcr.io/broad-gotc-prod/nomadic:latest`

1. Build locally (Apple Silicon users should keep `--platform=linux/amd64` as shown above).
2. Tag the local image with the GCR repository path.
3. Authenticate Docker to push to `us.gcr.io`.
4. Push the image.

```sh
docker tag nomadic:latest us.gcr.io/broad-gotc-prod/nomadic:latest
gcloud auth login
gcloud auth configure-docker us.gcr.io
docker push us.gcr.io/broad-gotc-prod/nomadic:latest
```

Optional: also push a dated or release tag for reproducibility.

```sh
docker tag nomadic:latest us.gcr.io/broad-gotc-prod/nomadic:2026-04-21
docker push us.gcr.io/broad-gotc-prod/nomadic:2026-04-21
```