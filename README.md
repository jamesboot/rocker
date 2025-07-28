# rocker
Setting up rocker singularity container

## 1. Import Rocker Image
Use the singularity pull command to import the desired Rocker image from Docker Hub into a (compressed, read-only) Singularity Image File:

`singularity pull docker://rocker/rstudio:4.4.2`

## 2. Run RStudio in SBATCH job

