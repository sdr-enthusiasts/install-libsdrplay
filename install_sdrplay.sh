#!/bin/bash

set -x

#shellcheck disable=SC2164,SC2086,SC2006
ARCH=`uname -m`
OSDIST="Unknown"

VERS="3.15"
MAJVERS="3"

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
    URL="https://www.sdrplay.com/software/SDRplay_RSP_API-Linux-3.15.2.run"
fi

if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
    echo "Arch set to ${ARCH}"
elif [ "$ARCH" == "aarch64" ]; then
    ARCH="arm64"
    echo "Arch set to ${ARCH}"
fi

echo "Cloning S6 files from Github..."

mkdir -p /etc/s6-overlay/s6-rc.d/sdrplay/dependencies.d || exit 1

# get the sdrplay files from github

curl -sS --location --output /etc/s6-overlay/s6-rc.d/sdrplay/run https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/sdrplay/run || exit 1
chmod 755 /etc/s6-overlay/s6-rc.d/sdrplay/run || exit 1

curl -sS --location --output /etc/s6-overlay/s6-rc.d/sdrplay/type https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/sdrplay/type || exit 1

curl -sS --location --output /etc/s6-overlay/s6-rc.d/user/contents.d/sdrplay https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/user/contents.d/sdrplay

curl -sS --location --output /etc/s6-overlay/scripts/sdrplay.sh https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/scripts/sdrplay.sh || exit 1
chmod 755 /etc/s6-overlay/scripts/sdrplay.sh || exit 1

# grab the sdr license service file from github

mkdir -p /etc/s6-overlay/s6-rc.d/03-sdrplay-license/dependencies.d || exit 1

# Below is an adaptation of the install script from the SDRPlay website
echo "Deploying SDRPlay version for architecture ${ARCH}"

echo "${URL}"

curl -sS --location --output /tmp/sdrplay.run "${URL}" || exit 1
chmod +x /tmp/sdrplay.run
pushd /tmp || exit 1
./sdrplay.run --target /tmp/sdrplay --noexec || exit 1
pushd /tmp/sdrplay || exit 1

if [ -d "/etc/udev/rules.d" ]; then
	echo -n "Udev rules directory found, adding rules..."
	curl -sS --location --output /etc/udev/rules.d/66-mirics.rules https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/66-mirics.rules || exit 1
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
curl -s --location --output /etc/udev/hwdb.d/20-sdrplay.hwdb https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/20-sdrplay.hwdb || exit 1
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

curl -sS --location --output /etc/s6-overlay/s6-rc.d/03-sdrplay-license/up https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/03-sdrplay-license/up || exit 1
chmod +x /etc/s6-overlay/s6-rc.d/03-sdrplay-license/up || exit 1

curl -sS --location --output /etc/s6-overlay/s6-rc.d/03-sdrplay-license/type https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/03-sdrplay-license/type || exit 1

curl -sS --location --output /etc/s6-overlay/s6-rc.d/user/contents.d/03-sdrplay-license https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/s6-rc.d/user/contents.d/03-sdrplay-license

curl -sS --location --output /etc/s6-overlay/scripts/03-sdrplay-license.sh https://raw.githubusercontent.com/sdr-enthusiasts/install-libsdrplay/main/s6-overlay/scripts/03-sdrplay-license.sh || exit 1

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
