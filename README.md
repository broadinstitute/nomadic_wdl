# nomadic_wdl container

This repo includes a simple Docker image that contains:

- `conda` + `mamba` + `python`
- `gsutil` (via Google Cloud CLI)
- `nomadic` (installed from Bioconda)
- `samtools >=1.20` (automatically included as a nomadic dependency)

## Build

### Apple Silicon (M1/M2/M3)

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
