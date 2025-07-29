#!/bin/sh
#SBATCH --time=08:00:00
#SBATCH --signal=USR2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192
#SBATCH --output=rstudio-server.job.%j

set -euxo pipefail

# Path to Singularity image and directories to bind
rstudio_sif="bioconductor_docker_3.21-R-4.5.1.sif"
TOBIND=/nemo/stp/babs/working/bootj

# Load Singularity
module load Singularity/3.6.4

# Host URL for SSH tunnel
HOSTURL=nemo.thecrick.org

# Package library directory in current working directory
export R_LIBS_USER="${PWD}/Rlibs"
mkdir -p "${R_LIBS_USER}"

# Log file for rserver output
rstudio_log="${PWD}/rstudio-server.${SLURM_JOB_ID}.log"
touch "${rstudio_log}"
echo "RStudio server log: ${rstudio_log}"

# Temporary working directory
workdir=$(python3 -c 'import tempfile; print(tempfile.mkdtemp())')
echo "Workdir: ${workdir}"

# Create rsession.sh wrapper
cat > "${workdir}/rsession.sh" <<END
#!/bin/sh
export R_LIBS_USER="${R_LIBS_USER}"
mkdir -p "\${R_LIBS_USER}"
export R_OPTIONS="--no-restore --no-save"
exec /usr/lib/rstudio-server/bin/rsession "\$@"
END
chmod +x "${workdir}/rsession.sh"

# Create rsession.conf
cat > "${workdir}/rsession.conf" << END
session-default-working-dir=${PWD}
session-default-new-project-dir=${PWD}
END

# Bind mounts
export SINGULARITY_BIND="${workdir}/rsession.sh:/etc/rstudio/rsession.sh,${workdir}/rsession.conf:/etc/rstudio/rsession.conf,${TOBIND},${workdir}/run:/run,${workdir}/tmp:/tmp,${workdir}/var/lib/rstudio-server:/var/lib/rstudio-server"

# RStudio env vars
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
export SINGULARITYENV_USER=$(id -un)
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# Allocate free port
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
echo "Allocated port: ${PORT}"

# Connection info
cat 1>&2 <<END
1. SSH tunnel from your workstation:

   ssh -N -L 8787:${HOSTNAME}.${HOSTURL}:${PORT} ${SINGULARITYENV_USER}@${HOSTNAME}.${HOSTURL}

   Open: http://localhost:8787

2. Log in:
   user: ${SINGULARITYENV_USER}
   pass: ${SINGULARITYENV_PASSWORD}

To stop session:
   scancel -f ${SLURM_JOB_ID}

Workdir: ${workdir}
Logfile: ${rstudio_log}
END

# Launch RStudio Server with logging
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
      > "${rstudio_log}" 2>&1

echo "rserver exited, see log: ${rstudio_log}"
