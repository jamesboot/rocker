#!/bin/sh

#SBATCH --time=08:00:00
#SBATCH --signal=USR2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192
#SBATCH --output=rstudio-server.job

# === CONFIG ===
RSTUDIO_SIF="bioconductor_docker_3.21-R-4.5.1.sif"
TOBIND="/nemo/stp/babs/working/bootj"
RENV_CACHE="/nemo/stp/babs/working/bootj/renv_cache/$(basename "${RSTUDIO_SIF}")"  # renv cache directory
HOSTURL="nemo.thecrick.org"

# Enable error handling and debugging
set -e  # Exit on error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${PWD}/rstudio.log"
}

# Function for important messages that should go to both log and job output
log_important() {
    log "$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Ensure log file exists and is empty
: > "${PWD}/rstudio.log"

# === Load Singularity ===
log "Loading Singularity module..."
module load Singularity/3.6.4 || { log_important "ERROR: Failed to load Singularity module"; exit 1; }
log "Singularity module loaded successfully"

# === R library location ===
export R_LIBS_USER="${PWD}/Rlibs"
mkdir -p "${R_LIBS_USER}"
# Pass into container explicitly
export SINGULARITYENV_R_LIBS_USER="${R_LIBS_USER}"

# === Checks ===
log "Performing initial checks..."
[ -f "$RSTUDIO_SIF" ] || { log_important "ERROR: Missing Singularity image $RSTUDIO_SIF"; exit 1; }
[ -d "$TOBIND" ] || { log_important "ERROR: Missing bind directory $TOBIND"; exit 1; }

# Create renv cache directory
log "Creating renv cache directory at ${RENV_CACHE}..."
mkdir -p "${RENV_CACHE}"
log "Initial checks passed successfully"

# === Working dirs ===
WORKDIR=$(python3 -c 'import tempfile; print(tempfile.mkdtemp())')
mkdir -p -m 700 \
    "${WORKDIR}/run" \
    "${WORKDIR}/tmp" \
    "${WORKDIR}/var/lib/rstudio-server"

# === Database config ===
cat > "${WORKDIR}/database.conf" <<END
provider=sqlite
directory=/var/lib/rstudio-server
END

# === RSession wrapper ===
cat > "${WORKDIR}/rsession.sh" <<END
#!/bin/sh
export R_LIBS_USER="${R_LIBS_USER}"
mkdir -p "${R_LIBS_USER}"
export R_OPTIONS="--no-restore --no-save"
export RENV_PATHS_CACHE="/renv-cache"
exec /usr/lib/rstudio-server/bin/rsession "\$@"
END
chmod +x "${WORKDIR}/rsession.sh"

# === RSession config ===
cat > "${WORKDIR}/rsession.conf" <<END
session-default-working-dir=${PWD}
session-default-new-project-dir=${PWD}
END

# === Bind mounts ===
export SINGULARITY_BIND="${WORKDIR}/rsession.sh:/etc/rstudio/rsession.sh,${WORKDIR}/rsession.conf:/etc/rstudio/rsession.conf,${TOBIND},${WORKDIR}/run:/run,${WORKDIR}/tmp:/tmp,${WORKDIR}/var/lib/rstudio-server:/var/lib/rstudio-server,${WORKDIR}/database.conf:/etc/rstudio/database.conf,${RENV_CACHE}:/renv-cache"

# === Env for RStudio ===
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
export SINGULARITYENV_USER=$(id -un)
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# === Port ===
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

# === Connection info ===
CONNECTION_INFO="1. SSH tunnel from your workstation using:
   ssh -N -L 8787:${HOSTNAME}.${HOSTURL}:${PORT} ${SINGULARITYENV_USER}@${HOSTNAME}.${HOSTURL}
   Then open: http://localhost:8787

2. Credentials:
   user: ${SINGULARITYENV_USER}
   password: ${SINGULARITYENV_PASSWORD}

WORKDIR: ${WORKDIR}
Log file: rstudio.log"

# Log connection info to both places as it's essential information
log_important "${CONNECTION_INFO}"

# === Start RStudio Server ===
log "Starting RStudio Server..."
log "Using port: ${PORT}"
log "Using workdir: ${WORKDIR}"
log "Using Singularity image: ${RSTUDIO_SIF}"

# Test if port is actually available
if ! nc -z localhost ${PORT}; then
    log "Port ${PORT} is available"
else
    log_important "ERROR: Port ${PORT} is already in use"
    exit 1
fi

# Start the server with verbose logging
log "Attempting to start RStudio Server with the following settings:"
log "Server user: ${SINGULARITYENV_USER}"
log "Auth PAM helper path: /usr/lib/rstudio-server/bin/pam-helper"
log "RSession path: /etc/rstudio/rsession.sh"

# Set verbose logging for rsession
export RSTUDIO_VERBOSE=1
export RSTUDIO_DEBUG=1

singularity exec --cleanenv \
    --workdir "${WORKDIR}" \
    "${RSTUDIO_SIF}" \
    /usr/lib/rstudio-server/bin/rserver \
      --www-port "${PORT}" \
      --auth-none=0 \
      --auth-pam-helper-path=/usr/lib/rstudio-server/bin/pam-helper \
      --auth-stay-signed-in-days=30 \
      --auth-timeout-minutes=0 \
      --server-user="${SINGULARITYENV_USER}" \
      --rsession-path=/etc/rstudio/rsession.sh \
      --server-daemonize=0 \
      >> "${PWD}/rstudio.log" 2>&1

# Check if rserver process started successfully
if [ $? -ne 0 ]; then
    log_important "ERROR: RStudio Server failed to start"
    log "Checking if rserver process is running..."
    ps aux | grep rserver | grep -v grep >> "${PWD}/rstudio.log"
    log "Checking port status..."
    netstat -tulpn | grep ${PORT} >> "${PWD}/rstudio.log"
fi
