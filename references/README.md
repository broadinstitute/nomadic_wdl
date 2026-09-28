# Reference genomes

Reference genome files `nomadic` needs at runtime. These are baked into the
Docker image (see `../Dockerfile`) so the WDL doesn't call `nomadic download`
at runtime — see the file layout `nomadic` expects in its own
`src/nomadic/download/references.py`.

- `AgPEST` comes from VectorBase, release `67` — a release counter (these
  VEuPathDB-family sites cut a new numbered release every few months), not a
  genome assembly version. The underlying assembly ("PEST") stays the same
  across many releases.
- `Pf3D7` comes from **Ensembl Genomes**, release `63` (filenames like
  `Plasmodium_falciparum.GCA000002765v3...`). As of `nomadic` 0.9.0, PlasmoDB
  can no longer be downloaded without auth, so `nomadic` itself switched
  Pf3D7's source to Ensembl Genomes — these files must match whatever source
  the installed `nomadic` version actually reads from (check
  `download/references.py` in the `nomadic` repo if upgrading).
