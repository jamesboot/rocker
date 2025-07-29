#!/bin/sh

#SBATCH --time=08:00:00
#SBATCH --signal=USR2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192
#SBATCH --output=rstudio-server.job.%j

set -euo pipefail
set -x  # enable shell debugging

# Path to Singularity image and bind mount directory
rstudio_sif="bioconductor_docker_3.21-R-4.5.1.sif"
TOBIND="/nemo/stp/babs/working/bootj"

# Load Singularity
module load Singularity/3.6.4

# Host URL for SSH tunnel
HOSTURL="nemo.thecrick.org"

# Package library directory in current working directory
export R_LIBS_USER="${PWD}/Rlibs"
mkdir -p "${R_LIBS_USER}"

# Verify image and bind directory exist
if [ ! -f "$rstudio_sif" ]; then
  echo "ERROR: Singularity image not found: $rstudio_sif" >&2
  exit 1
fi
if [ ! -d "$TOBIND" ]; then
  echo "ERROR: Bind directory not found: $TOBIND" >&2
  exit 1
fi

# Create temporary working directory
workdir=$(python3 -c 'import tempfile; print(tempfile.mkdtemp())')
mkdir -p -m 700 \
  "${workdir}/run" \
  "${workdir}/tmp" \
  "${workdir}/var/lib/rstudio-server"

# Create database config
cat > ${workdir}/database.conf <<END
provider=sqlite
directory=/var/lib/rstudio-server
END

# rsession wrapper
cat > "${workdir}/rsession.sh" <<"END"
#!/bin/sh
export R_LIBS_USER="${R_LIBS_USER}"
mkdir -p "\${R_LIBS_USER}"
export R_OPTIONS="--no-restore --no-save"
exec /usr/lib/rstudio-server/bin/rsession "\$@"
END
chmod +x "${workdir}/rsession.sh"

# rsession config
cat > "${workdir}/rsession.conf" << END
session-default-working-dir=${PWD}
session-default-new-project-dir=${PWD}
END

# Bind mounts
export SINGULARITY_BIND="${workdir}/rsession.sh:/etc/rstudio/rsession.sh,${workdir}/rsession.conf:/etc/rstudio/rsession.conf,${TOBIND},${workdir}/run:/run,${workdir}/tmp:/tmp,${workdir}/var/lib/rstudio-server:/var/lib/rstudio-server,${workdir}/database.conf:/etc/rstudio/database.conf"

# Environment variables for RStudio
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
export SINGULARITYENV_USER=$(id -un)
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# Find unused port
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

# Print connection info
cat 1>&2 <<END
1. SSH tunnel from your workstation using:
   ssh -N -L 8787:${HOSTNAME}.${HOSTURL}:${PORT} ${SINGULARITYENV_USER}@${HOSTNAME}.${HOSTURL}
   Then open: http://localhost:8787

2. Credentials:
   user: ${SINGULARITYENV_USER}
   password: ${SINGULARITYENV_PASSWORD}

Workdir: ${workdir}
Log file: ${workdir}/rstudio.log
END

# Run RStudio Server inside container, log output to file
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
      2>&1 | tee "${workdir}/rstudio.log"

# If it exits quickly, print the last 20 lines of the log
echo "===== RStudio Server log tail ====="
tail -n 20 "${workdir}/rstudio.log" || true
