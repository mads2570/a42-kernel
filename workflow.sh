#!/bin/bash

echo "------------------------------------------------------"
echo "---             RAD-KERNEL-BUILD-SCRIPT            ---"
echo "------------------------------------------------------"

DATE=$(date +'%Y%m%d-%H%M')
JOBS=$(nproc)
KERNELDIR=$(pwd)
DEVICE=$1
VERSION=10
CLEAN=$3

echo "<${DEVICE}> has been selected!"

if [ "${DEVICE}" == "a42" ]; then
		export DEFCONFIG=a42xq_eur_open_defconfig;
		export AK3_a42_PATH=ak3-a42;
	
	fi;
	
echo "-----------------------------------------"

read -p "Type version number > " vr
export VERSION=$vr
if [ "$vr" = "" -o "$vr" = "exit" ]; then
     echo ""
     echo "No version selected!"
     echo "Exiting now!"
     echo ""
     exit 0
else
     echo ""
     echo "<${VERSION}> version number has been set!"
     echo ""
fi;
	
read -p "Clean source (y/n) > " yn
if [ "$yn" = "Y" -o "$yn" = "y" ]; then
     echo "Cleaning Source!"
     export CLEAN=yes
else
     echo "Not cleaning source!"
     export CLEAN=no
fi

export LOCALVERSION=-RAD-${VERSION}-${DATE}-AOSP

export ARCH=arm64
export PATH="$(pwd)/clang/bin/:$(pwd)/toolchain/bin:${PATH}"
export CROSS_COMPILE=$(pwd)/toolchain/bin/aarch64-linux-gnu-

if [ "${CLEAN}" == "yes" ]; then
	echo "Executing make clean & make mrproper!";
	BUILD_START=$(date +"%s");
	rm -rf out;
	mkdir -p out;
	make O=out clean && make O=out mrproper;
  elif [ "${CLEAN}" == "no" ]; then
	echo "Initiating Dirty build!";
	rm -rf ${KERNELDIR}/out/arch/arm64/boot/Image;
	rm -rf ${KERNELDIR}/out/arch/arm64/boot/a42xq_eur_open.img;
	BUILD_START=$(date +"%s");
	fi;
	
echo "-----------------------------------------"	

echo ....................................
echo ....................................
echo ...""BUILDING KERNEL "".............
echo ....................................
echo ....................................
make O=out KERNEL_MAKE_ENV-${DEFCONFIG}_defconfig && script -q ~/Compile.log -c "
make O=out CC=clang -j${JOBS}"

if [ ! -e ${KERNELDIR}/RAD/logs ]; then
		mkdir ${KERNELDIR}/RAD/logs;
	fi;
	
if [ ! -e ${KERNELDIR}/RAD/Releases ]; then
		mkdir ${KERNELDIR}/RAD/Releases;
	fi;
	
if [ -e ${KERNELDIR}/out/arch/arm64/boot/Image ]; then
        echo ""
        echo ""Making AK3 zip!""
        echo ""
	rm -rf ${KERNELDIR}/RAD/${AK3_a42xq_PATH}/dt.img
	rm -rf ${KERNELDIR}/RAD/${AK3_a42xq_PATH}/Image
	rm -rf ${KERNELDIR}/RAD/${AK3_a42xq_PATH}/kernel.zip
	
else
	echo ""
	echo "Kernel didnt build successfully!"
	echo "No zIMAGE in out dir"
	export BUILD=FAIL
	echo "Copying Logs!"
	rm -rf ${KERNELDIR}/RAD/logs/build_fail-${VERSION}-${DATE}-${DEFCONFIG}.log
	mv ~/Compile.log ${KERNELDIR}/RAD/Releases/${VERSION}/build_fail-${VERSION}-${DATE}-${DEFCONFIG}.log
fi;

if [ "${BUILD}" == "FAIL" ]; then
	export log=Y
fi;

if [ "$log" = "Y" -o "$log" = "y" ]; then
     echo "Exiting!"
     exit 0
  elif [ "$log" = "N" -o "$log" = "n" ]; then
	echo "Exiting!";
	exit 0
fi;

	echo ""
	echo "Copying zImage & dt.img to AK3 dir!"
	echo ""
if [ "${DEVICE}" == "a42xq" ]; then
		cp ${KERNELDIR}/out/arch/arm64/boot/Image ${KERNELDIR}/RAD/${AK3_a42xq_PATH};
		cp ${KERNELDIR}/out/arch/arm64/boot/dtb_a42xq_eur_open.img ${KERNELDIR}/RAD/${AK3_a42xq_PATH};
		
		
	fi;
		
	echo ""
	echo "Zipping up AK3!"
	echo ""
if [ "${DEVICE}" == "a42xq" ]; then
	cd $(pwd)/RAD/${AK3_a42xq_PATH}
	mv dtb_dreamlte.img dt.img
	zip -r9 kernel.zip * -x README.md kernel.zip/
	mkdir ${KERNELDIR}/RAD/Releases/${VERSION}
	mv kernel.zip ${KERNELDIR}/RAD/Releases/${VERSION}/RAD-${VERSION}-a42xq_eur_open-${DATE}.zip
	
    fi;
    
	BUILD_END=$(date +"%s");
	DIFF=$(($BUILD_END - $BUILD_START));
	echo "";
	echo "Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.";
	echo ""


