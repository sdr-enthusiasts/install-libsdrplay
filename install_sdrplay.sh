#!/bin/bash

set -x

#shellcheck disable=SC2164,SC2086,SC2006
ARCH=`uname -m`
OSDIST="Unknown"

VERS="3.15"
MAJVERS="3"
SDRPLAY_SHA256="3a97ca764263bbe76fb0f2220e6408942357e8864c19e1408a6d6987af382fe3"

if [ -f "/etc/os-release" ]; then
    OSDIST=$(sed '1q;d' /etc/os-release)
    echo "DISTRIBUTION ${OSDIST}"
    case "$OSDIST" in
        *Alpine*)
            ARCH="Alpine64"
        ;;
    esac
fi

echo "Architecture: ${ARCH}"
echo "API Version: ${VERS}"

# if arch is arm, armhf , set URL to ARM version
# if arch is x86_64, set URL to x86_64 version
# if arch is aarch64, set URL to aarch64 version

# https://www.sdrplay.com/software/SDRplay_RSP_API-ARM32-3.07.2.run
# https://www.sdrplay.com/software/SDRplay_RSP_API-ARM64-3.07.1.run
# https://www.sdrplay.com/software/SDRplay_RSP_API-Linux-3.07.1.run

if [ "${ARCH}" != "aarch64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "Warning: Unsupported architecture ${ARCH} detected"
    echo "Unsupported ARCH. Exiting..."
    exit 1
else
    URL="https://sdrplay.com/download/hardware-api-linux/?wpdmdl=1906"
fi

if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
    echo "Arch set to ${ARCH}"
elif [ "$ARCH" == "aarch64" ]; then
    ARCH="arm64"
    echo "Arch set to ${ARCH}"
fi

# Fetch the vendor installer up front, before we create any directories or
# install any service files. If SDRplay's download is broken or has moved we
# want to fail here, with the image untouched, rather than half-installing and
# then dying on a confusing error further down.
echo "Downloading SDRplay API installer from ${URL}"

# --fail is load-bearing: without it curl happily writes a 404 error page to
# the output file and exits 0, so the failure only surfaces later when the
# "installer" is executed and the shell chokes on HTML.
if ! curl -sS --fail --location --output /tmp/sdrplay.run "${URL}"; then
    echo "ERROR: could not download the SDRplay API installer from:" >&2
    echo "  ${URL}" >&2
    echo "The SDRplay download endpoint is unreachable, or the file has moved." >&2
    echo "This is an upstream vendor problem and cannot be worked around here." >&2
    exit 1
fi

# SDRplay's download URL does not include a version and may be repointed. Pin
# the known 3.15.2 payload so a vendor-side change cannot silently enter an
# image build.
if ! echo "${SDRPLAY_SHA256}  /tmp/sdrplay.run" | sha256sum --check --status; then
    echo "ERROR: SDRplay API installer checksum mismatch." >&2
    echo "Expected the published SDRplay API 3.15.2 installer." >&2
    exit 1
fi

echo "Cloning S6 files from Github..."

mkdir -p /etc/s6-overlay/s6-rc.d/sdrplay/dependencies.d || exit 1
mkdir -p /etc/s6-overlay/scripts || exit 1

# s6-overlay >= v3.2.3.1 moved the user bundle definitions from
# /etc/s6-overlay/s6-rc.d/user to /etc/s6-overlay/user-bundles.d/user. Its
# compatibility shim honours exactly ONE of the two locations: if s6-rc.d/user
# exists, user-bundles.d is ignored wholesale. Mirror that precedence exactly, so
# we always register in the directory the runtime will actually read.
if [ -d /etc/s6-overlay/s6-rc.d/user ]; then
    # Legacy layout in play, either because s6-overlay is < v3.2.3.1 or because
    # an image layer below us still ships the deprecated directory.
    S6_USER_BUNDLE="/etc/s6-overlay/s6-rc.d/user/contents.d"
elif [ -d /etc/s6-overlay/user-bundles.d/user/contents.d ]; then
    S6_USER_BUNDLE="/etc/s6-overlay/user-bundles.d/user/contents.d"
else
    S6_USER_BUNDLE="/etc/s6-overlay/s6-rc.d/user/contents.d"
fi
echo "Registering services in ${S6_USER_BUNDLE}"
mkdir -p "${S6_USER_BUNDLE}" || exit 1

# get the sdrplay files from github

curl -sS --fail --location --output /etc/s6-overlay/s6-rc.d/sdrplay/run https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/sdrplay/run || exit 1
chmod 755 /etc/s6-overlay/s6-rc.d/sdrplay/run || exit 1

curl -sS --fail --location --output /etc/s6-overlay/s6-rc.d/sdrplay/type https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/sdrplay/type || exit 1

# Bundle registration markers are empty files; create them directly rather than
# fetching zero bytes over the network.
touch "${S6_USER_BUNDLE}/sdrplay" || exit 1

curl -sS --fail --location --output /etc/s6-overlay/scripts/sdrplay.sh https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/scripts/sdrplay.sh || exit 1
chmod 755 /etc/s6-overlay/scripts/sdrplay.sh || exit 1

# grab the sdr license service file from github

mkdir -p /etc/s6-overlay/s6-rc.d/03-sdrplay-license/dependencies.d || exit 1

# Below is an adaptation of the install script from the SDRPlay website
echo "Deploying SDRPlay version for architecture ${ARCH}"

echo "${URL}"

chmod +x /tmp/sdrplay.run
pushd /tmp || exit 1
./sdrplay.run --target /tmp/sdrplay --noexec || exit 1
pushd /tmp/sdrplay || exit 1

if [ -d "/etc/udev/rules.d" ]; then
	echo -n "Udev rules directory found, adding rules..."
	curl -sS --fail --location --output /etc/udev/rules.d/66-mirics.rules https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/66-mirics.rules || exit 1
	chmod 644 /etc/udev/rules.d/66-mirics.rules || exit 1
    echo "Done"
else
	echo " "
	echo "ERROR: udev rules directory not found, add udev support and run the"
	echo "installer again. udev support can be added by running..."
	echo "apt install libudev-dev"
	echo " "
	exit 1
fi

if [ ! -d "/etc/udev/hwdb.d" ]; then
    echo "Creating udev hwdb rules directory..."
    mkdir -p /etc/udev/hwdb.d || exit 1
fi

echo -n "Adding udev hwdb rules..."
curl -sS --fail --location --output /etc/udev/hwdb.d/20-sdrplay.hwdb https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/20-sdrplay.hwdb || exit 1
chmod 644 /etc/udev/hwdb.d/20-sdrplay.hwdb || exit 1
echo "Done"

INSTALLLIBDIR="/usr/local/lib"
INSTALLINCDIR="/usr/local/include"
INSTALLBINDIR="/usr/bin"

mkdir -p ${INSTALLLIBDIR} || exit 1
mkdir -p ${INSTALLINCDIR} || exit 1
mkdir -p ${INSTALLBINDIR} || exit 1

echo -n "Installing ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS}..."
rm -f ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS} || exit 1
cp -f "${ARCH}"/libsdrplay_api.so.${VERS} ${INSTALLLIBDIR}/. || exit 1
chmod 644 ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS} || exit 1
rm -f ${INSTALLLIBDIR}/libsdrplay_api.so.${MAJVERS} || exit 1
ln -s ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS} ${INSTALLLIBDIR}/libsdrplay_api.so.${MAJVERS} || exit 1
rm -f ${INSTALLLIBDIR}/libsdrplay_api.so || exit 1
ln -s ${INSTALLLIBDIR}/libsdrplay_api.so.${MAJVERS} ${INSTALLLIBDIR}/libsdrplay_api.so || exit 1
echo "Done"

echo -n "Installing header files in ${INSTALLINCDIR}..."
cp -f inc/sdrplay_api*.h ${INSTALLINCDIR}/. || exit 1
chmod 644 ${INSTALLINCDIR}/sdrplay_api*.h || exit 1
ls -l ${INSTALLINCDIR}/sdrplay_api*.h || exit 1
echo "Done"

echo -n "Installing API Service in ${INSTALLBINDIR}..."
cp -f "${ARCH}"/sdrplay_apiService ${INSTALLBINDIR}/sdrplay_apiService  || exit 1
chmod 755 ${INSTALLBINDIR}/sdrplay_apiService || exit 1
ls -l ${INSTALLBINDIR}/sdrplay_apiService || exit 1
echo "Done"

ldconfig

curl -sS --fail --location --output /etc/s6-overlay/s6-rc.d/03-sdrplay-license/up https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/03-sdrplay-license/up || exit 1
chmod +x /etc/s6-overlay/s6-rc.d/03-sdrplay-license/up || exit 1

curl -sS --fail --location --output /etc/s6-overlay/s6-rc.d/03-sdrplay-license/type https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/03-sdrplay-license/type || exit 1

touch "${S6_USER_BUNDLE}/03-sdrplay-license" || exit 1

curl -sS --fail --location --output /etc/s6-overlay/scripts/03-sdrplay-license.sh https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/scripts/03-sdrplay-license.sh || exit 1

chmod +x /etc/s6-overlay/scripts/03-sdrplay-license.sh || exit 1

cp sdrplay_license.txt /sdrplay_license.txt

# enable installation without soapy (which is not needed when used with SDRPlay's "special" dump1090 version)
if [[ "$1" == "--no-soapy" ]]; then exit 0; fi

echo "Installing SoapySDRPlay"

git clone https://github.com/pothosware/SoapySDRPlay.git /src/SoapySDRPlay
pushd /src/SoapySDRPlay || exit 1
mkdir build || exit 1
pushd build || exit 1
cmake -D CMAKE_FIND_DEBUG_MODE=ON .. || exit 1
make || exit 1
make install || exit 1
popd || exit 1
popd || exit 1
ldconfig
# remove the source code
rm -rf /src/SoapySDRPlay
