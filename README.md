# rocker

Setting up rocker singularity container and running remote rstudio session on HPC.

## 1. Import Rocker Image (first time only)

### a) Setup a directory/cache for singularity images

This is a permanent directory where you will store singularity images and refer to them in your `rstudio-server.sh` script

```
mkdir -p /path/to/dir
cd -p /path/to/dir
```

### b) Load singularity module

```
module load Singularity/3.6.4
```

### c) Pull image

Use the singularity pull command to import the desired Rocker image from Docker Hub into a (compressed, read-only) Singularity Image File:

```
singularity pull docker://bioconductor/bioconductor_docker:3.21-R-4.5.1
```

## 2. Run RStudio in SBATCH job

### a) Edit `rstudio-server.sh`

At the top of the script:

- Specify path to the singularity image downloaded previously - add to `RSTUDIO_SIF` variable at top of script
- Add relevant `nemo` locations for the `SINGULARITY_BIND` variable - add to `TOBIND` at top of script, separate by commas
- Specify path to a folder where `renv` will cache downloads, assign to `RENV_CACHE` - directory doesn't need to exist it will be created if not

Do not edit anything else.

### b) Run script

```
sbatch rstudio-server.sh
```

### c) Inspect the output file for instructions

The job output contains instructions on how to login to the remote rstudio session.

```
cat rstudio-server.job
```

## 3. Setup `renv` (first time only)

### a) Install `renv`

```
install.packages("renv")
```

### b) Initialise `renv` project 

```
renv::init()
```

### c) Install relevant libraries and update lock file

Installing libraries
```
renv::install("Seurat") # Install from CRAN
renv::install("bioc::DESeq2") # Install from bioconductor example
renv::install("jokergoo/ComplexHeatmap") # Install from github example
```

Snapshotting (often done automatically but may need ot be done from time to time):
```
renv::snapshot()
```







