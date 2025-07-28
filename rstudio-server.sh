#!/bin/sh

#SBATCH --time=08:00:00
#SBATCH --signal=USR2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192
#SBATCH --output=rstudio-server.job.%j

set -euo pipefail

# Load Singularity
module load Singularity/3.6.4

# Set container image path (update this if necessary)
rstudio_sif="rstudio_4.4.2.sif"

# Set host URL for SSH tunneling
HOSTURL=nemo.thecrick.org

# Create temp working directory
workdir=$(python3 -c 'import tempfile; print(tempfile.mkdtemp())')

if [ -z "$workdir" ]; then
  echo "Failed to create temporary workdir" >&2
  exit 1
fi

# Set R_LIBS_USER to avoid conflicts with host R libraries
cat > "${workdir}/rsession.sh" <<"END"
#!/bin/sh
export R_LIBS_USER=${HOME}/R/rocker-rstudio/4.4.2
mkdir -p "${R_LIBS_USER}"
# Optional custom R config:
# export R_PROFILE_USER=/path/to/Rprofile
# export R_ENVIRON_USER=/path/to/Renviron
exec /usr/lib/rstudio-server/bin/rsession "${@}"
END

chmod +x "${workdir}/rsession.sh"

# Directories to bind to container
TOBIND=/nemo/stp/babs/working/bootj
export SINGULARITY_BIND="${workdir}/rsession.sh:/etc/rstudio/rsession.sh,${TOBIND}"

# RStudio Server environment configuration
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
export SINGULARITYENV_USER=$(id -un)
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# Get an unused port
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

cat 1>&2 <<END
1. SSH tunnel from your workstation using the following command:

   ssh -N -L 8787:${HOSTNAME}.${HOSTURL}:${PORT} ${SINGULARITYENV_USER}@${HOSTNAME}.${HOSTURL}

   and point your web browser to http://localhost:8787

2. Log in to RStudio Server using the following credentials:

   user: ${SINGULARITYENV_USER}
   password: ${SINGULARITYENV_PASSWORD}

To stop the session:
1. Exit the RStudio session (power button in top right)
2. Run on login node: scancel -f ${SLURM_JOB_ID}
END

# Launch RStudio Server in container
singularity exec --cleanenv \
    --scratch /run,/tmp,/var/lib/rstudio-server \
    --workdir "${workdir}" \
    "${rstudio_sif}" \
    rserver \
      --www-port "${PORT}" \
      --auth-none=0 \
      --auth-pam-helper-path=pam-helper \
      --auth-stay-signed-in-days=30 \
      --auth-timeout-minutes=0 \
      --server-user="${SINGULARITYENV_USER}" \
      --rsession-path=/etc/rstudio/rsession.sh

printf 'rserver exited\n' 1>&2
