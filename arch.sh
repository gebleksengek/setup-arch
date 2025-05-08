#!/bin/sh

set -e

user=$USER
case "$1" in
	-r | --root) user='root'; shift;;
esac

rootfs=$(cd "$(dirname "$0")"/.. && pwd)
oldpwd=$(pwd)
export | sudo tee "$rootfs/bounce/env.sh" >/dev/null

exec sudo "$rootfs/bin/arch-chroot" "$rootfs" \
	/bin/su "$user" \
		/bin/sh -lc ". /bounce/env.sh; cd '$oldpwd' 2>/dev/null; exec \"\$@\"" -- \
			/bin/bash -eo pipefail "$@"
