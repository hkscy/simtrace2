#!/bin/bash

TOPDIR=`pwd`

if ! [ -x "$(command -v osmo-build-dep.sh)" ]; then
	echo "Error: We need to have scripts/osmo-deps.sh from http://git.osmocom.org/osmo-ci/ in PATH !"
	exit 2
fi

set -e

publish="$1"
base="$PWD"
deps="$base/deps"
inst="$deps/install"
export deps inst

osmo-clean-workspace.sh

mkdir "$deps" || true

osmo-build-dep.sh libosmocore "" '--disable-doxygen --enable-gnutls'

# verify only after building the dependency (to ensure we have most recent source of dependency)
verify_value_string_arrays_are_terminated.py $(find . -name "*.[hc]")

export PKG_CONFIG_PATH="$inst/lib/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$inst/lib"

BUILDS=""
BUILDS+="simtrace/dfu simtrace/blupdate simtrace/trace simtrace/cardem "
BUILDS+="qmod/dfu qmod/blupdate qmod/cardem "
BUILDS+="owhw/dfu owhw/blupdate owhw/cardem "
BUILDS+="octsimtest/cardem "
BUILDS+="ngff_cardem/dfu ngff_cardem/blupdate ngff_cardem/cardem ngff_cardem/trace "

cd $TOPDIR/firmware
for build in $BUILDS; do
	board=`echo $build | cut -d "/" -f 1`
	app=`echo $build | cut -d "/" -f 2`
	echo
	echo "=============== $board / $app START  =============="
	make BOARD="$board" APP="$app"
	echo "=============== $board / $app RES:$? =============="
done

echo
echo "=============== FIRMWARE TESTS ==========="
cd $TOPDIR/firmware/test
make clean
make
./card_emu_test
make clean

echo
echo "=============== HOST START  =============="
cd $TOPDIR/host
autoreconf --install --force
./configure --enable-sanitize --enable-werror
$MAKE $PARALLEL_MAKE
#$MAKE distcheck || cat-testlogs.sh
make dist

#if [ "$WITH_MANUALS" = "1" ] && [ "$PUBLISH" = "1" ]; then
#	make -C "$base/doc/manuals" publish
#fi

if [ "x$publish" = "x--publish" ]; then
	echo
	echo "=============== UPLOAD BUILD  =============="
	$TOPDIR/contrib/prepare_upload.sh

	cat > "/build/known_hosts" <<EOF
[ftp.osmocom.org]:48 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDgQ9HntlpWNmh953a2Gc8NysKE4orOatVT1wQkyzhARnfYUerRuwyNr1GqMyBKdSI9amYVBXJIOUFcpV81niA7zQRUs66bpIMkE9/rHxBd81SkorEPOIS84W4vm3SZtuNqa+fADcqe88Hcb0ZdTzjKILuwi19gzrQyME2knHY71EOETe9Yow5RD2hTIpB5ecNxI0LUKDq+Ii8HfBvndPBIr0BWYDugckQ3Bocf+yn/tn2/GZieFEyFpBGF/MnLbAAfUKIdeyFRX7ufaiWWz5yKAfEhtziqdAGZaXNaLG6gkpy3EixOAy6ZXuTAk3b3Y0FUmDjhOHllbPmTOcKMry9
[ftp.osmocom.org]:48 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPdWn1kEousXuKsZ+qJEZTt/NSeASxCrUfNDW3LWtH+d8Ust7ZuKp/vuyG+5pe5pwpPOgFu7TjN+0lVjYJVXH54=
[ftp.osmocom.org]:48 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK8iivY70EiR5NiGChV39gRLjNpC8lvu1ZdHtdMw2zuX
EOF
	SSH_COMMAND="ssh -o 'UserKnownHostsFile=/build/known_hosts' -p 48"
	rsync --archive --verbose --compress --delete --rsh "$SSH_COMMAND" $TOPDIR/firmware/bin/*-latest.{bin,elf} binaries@ftp.osmocom.org:web-files/simtrace2/firmware/latest/
	rsync --archive --verbose --compress --rsh "$SSH_COMMAND" --exclude $TOPDIR/firmware/bin/*-latest.{bin,elf} $TOPDIR/firmware/bin/*-*-*-*.{bin,elf} binaries@ftp.osmocom.org:web-files/simtrace2/firmware/all/
fi

echo
echo "=============== HOST CLEAN  =============="
$MAKE maintainer-clean

echo
echo "=============== FIRMWARE CLEAN  =============="
cd $TOPDIR/firmware/
for build in $BUILDS; do
	board=`echo $build | cut -d "/" -f 1`
	app=`echo $build | cut -d "/" -f 2`
	make BOARD="$board" APP="$app" clean
done

osmo-clean-workspace.sh
