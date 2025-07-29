#!/bin/sh

#SBATCH --time=08:00:00
#SBATCH --signal=USR2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192
#SBATCH --output=rstudio-server.job.%j

set -euo pipefail
set -x  # Debug: show each command as it's executed

# Path to Singularity image and directories to bind
rstudio_sif="bioconductor_docker_3.21-R-4.5.1.sif"
TOBIND="/nemo/stp/babs/working/bootj"

# Load Singularity
module load Singularity/3.6.4

# Host URL for SSH tunnel
HOSTURL="nemo.thecrick.org"

# --- Sanity checks ---
if [ ! -f "${rstudio_sif}" ]; then
  echo "ERROR: Singularity image not found: ${rstudio_sif}" >&2
  exit 1
fi

if [ ! -d "${TOBIND}" ]; then
  echo "ERROR: Bind directory not found: ${TOBIND}" >&2
  exit 1
fi

# Create temporary working directory
workdir=$(python3 -c 'import tempfile; print(tempfile.mkdtemp())')
if [ -z "$workdir" ]; then
  echo "ERROR: Failed to create temporary workdir" >&2
  exit 1
fi

mkdir -p -m 700 "${workdir}"/{run,tmp,var/lib/rstudio-server}

# --- Create debug-enabled rsession.sh ---
cat > "${workdir}/rsession.sh" <<'END'
#!/bin/sh
echo "[$(date)] rsession.sh invoked" >> "${HOME}/rsession_debug.log"
export OMP_NUM_THREADS=${SLURM_JOB_CPUS_PER_NODE:-1}
export R_LIBS_USER="${HOME}/R/rocker-rstudio/bioconductor_docker_3.21-R-4.5.1"
mkdir -p "${R_LIBS_USER}"
export R_OPTIONS="--no-restore --no-save"
exec /usr/lib/rstudio-server/bin/rsession "$@"
END

chmod +x "${workdir}/rsession.sh"

# --- Create rsession.conf to set working directory ---
cat > "${workdir}/rsession.conf" <<END
session-default-working-dir=${PWD}
session-default-new-project-dir=${PWD}
END

# --- Bind directories ---
export SINGULARITY_BIND="${workdir}/rsession.sh:/etc/rstudio/rsession.sh,${workdir}/rsession.conf:/etc/rstudio/rsession.conf,${TOBIND},${workdir}/run:/run,${workdir}/tmp:/tmp,${workdir}/var/lib/rstudio-server:/var/lib/rstudio-server"

# --- Environment variables for RStudio Server ---
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
export SINGULARITYENV_USER=$(id -un)
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# --- Allocate an unused port ---
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
if [ -z "$PORT" ]; then
  echo "ERROR: Failed to allocate a port" >&2
  exit 1
fi

# --- Connection instructions ---
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

Workdir: ${workdir}
END

# --- Run RStudio Server in the foreground with debug logging ---
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
      --rsession-path=/etc/rstudio/rsession.sh \
      --server-daemonize=0 \
      --log-stderr

printf 'rserver exited\n' 1>&2
