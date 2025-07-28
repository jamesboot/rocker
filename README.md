# rocker

Setting up rocker singularity container and running remote rstudio session on HPC.

## 1. Import Rocker Image
Use the singularity pull command to import the desired Rocker image from Docker Hub into a (compressed, read-only) Singularity Image File:

`singularity pull docker://rocker/rstudio:4.4.2`

## 2. Run RStudio in SBATCH job

### a) Edit `rstudio-server.sh`

- Add relevant `nemo` locations for `SINGULARITY_BIND`

### b) Run script

- Submit: `sbatch rstudio-server.sh`
