# rocker

Setting up rocker singularity container and running remote rstudio session on HPC.

## 1. Import Rocker Image

### a) Navigate to project / working directory.

```
cd /path/to/dir
```

### b) Load singularity module

```
module load Singularity/3.6.4
```

### c) Pull image

Use the singularity pull command to import the desired Rocker image from Docker Hub into a (compressed, read-only) Singularity Image File:

```
singularity pull docker://rocker/rstudio:4.4.2
```

## 2. Run RStudio in SBATCH job

### a) Edit `rstudio-server.sh`

- Add relevant `nemo` locations for the `SINGULARITY_BIND` variable - add to `TOBIND` at top of script, separate by commas

### b) Run script

- Submit:
```
sbatch rstudio-server.sh`
```
