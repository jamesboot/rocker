#!/bin/sh

#SBATCH --time=08:00:00
#SBATCH --signal=USR2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192
#SBATCH --output=rstudio-server.job.%j

# Path to Singularity image and directories to bind
rstudio_sif="bioconductor_docker_3.21-R-4.5.1.sif"
TOBIND=/nemo/stp/babs/working/bootj

set -euo pipefail

# Load Singularity
module load Singularity/3.6.4

# Host URL for SSH tunnel
HOSTURL=nemo.thecrick.org

# Create temporary working directory
workdir=$(python3 -c 'import tempfile; print(tempfile.mkdtemp())')

if [ -z "$workdir" ]; then
  echo "Failed to create temporary workdir" >&2
  exit 1
fi

# Create rsession.sh wrapper to isolate R_LIBS_USER and suppress session restore
cat > "${workdir}/rsession.sh" <<"END"
#!/bin/sh
export R_LIBS_USER=${HOME}/R/rocker-rstudio/bioconductor_docker_3.21-R-4.5.1
mkdir -p "${R_LIBS_USER}"
# Prevent R from restoring saved sessions by default
export R_OPTIONS="--no-restore --no-save"
exec /usr/lib/rstudio-server/bin/rsession "${@}"
END

chmod +x "${workdir}/rsession.sh"

# Create rsession.conf to set default working and project directory
cat > "${workdir}/rsession.conf" << END
session-default-working-dir=${PWD}
session-default-new-project-dir=${PWD}
END

# Directories to bind into the container
export SINGULARITY_BIND="${workdir}/rsession.sh:/etc/rstudio/rsession.sh,${workdir}/rsession.conf:/etc/rstudio/rsession.conf,${TOBIND}"

# RStudio Server environment configuration
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
export SINGULARITYENV_USER=$(id -un)
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# Allocate an unused port for RStudio Server
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

# Output connection instructions to stderr
cat 1>&2 <<END
1. SSH tunnel from your workstation using:

   ssh -N -L 8787:${HOSTNAME}.${HOSTURL}:${PORT} ${SINGULARITYENV_USER}@${HOSTNAME}.${HOSTURL}

   Then open your browser at: http://localhost:8787

2. Log in to RStudio Server with:

   user: ${SINGULARITYENV_USER}
   password: ${SINGULARITYENV_PASSWORD}

To stop your session:

1. Click the power button in RStudio
2. Or run: scancel -f ${SLURM_JOB_ID}
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
