# Where everything lives, sourced by the build scripts (repository layout).
# A = this directory (scripts/).
R="$(cd "$A/.." && pwd)"
SCRIPTS=$R/scripts                           # build-*.sh, check-image.sh, ...
PKGS_DIR=$R/packaging                        # Arch Linux ARM PKGBUILD directories
SETUP_SH=$R/configs/rootfs/setup.sh          # image setup, run in the container
TWRP_BINARY=$R/configs/twrp/update-binary    # TWRP installer
WORK_DIR=$R/work                             # scratch, not versioned
LOCAL_REPO=$R/work/repo                      # local pacman repository
OUT_BASE=$R/work/out                         # images: $OUT_BASE/$EDITION
DL_DIR=$R/work/dl                            # ArchLinuxARM-aarch64-latest.tar.gz
ARTIFACTS=$R/artifacts                       # TWRP zips
PMOS_DEVICE=$R/packaging/postmarketos/device-samsung-r9q
VENDOR_FW=${VENDOR_FW:-$R/work/vendor-firmware}   # copy of the phone's /vendor/firmware
PMB_WORK=${PMB_WORK:-$HOME/.local/var/pmbootstrap} # pmbootstrap work directory
# private, never versioned (only for your own images, without PUBLIC=1)
CRED=${CRED:-$R/work/CREDENTIALS.txt}              # password=...
PMB_CFG=${PMB_CFG:-$R/work/pmbootstrap-r9q.cfg}    # user, locale, timezone
KNOWN_HOSTS=${KNOWN_HOSTS:-$R/work/known_hosts}    # the phone's SSH host key
VERSION_FILE=$R/VERSION
