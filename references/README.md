# Reference genomes

Reference genome files `nomadic` needs at runtime. These are baked into the
Docker image (see `../Dockerfile`) so the WDL doesn't call `nomadic download`
at runtime — see the file layout `nomadic` expects in its own
`src/nomadic/download/references.py`.

The `67` in these filenames is **not** a genome assembly version — it's
PlasmoDB/VectorBase's own release counter (these VEuPathDB-family sites cut a
new numbered release every few months with updated annotations, while the
underlying assembly, e.g. "3D7" or "PEST", stays the same across many
releases).
