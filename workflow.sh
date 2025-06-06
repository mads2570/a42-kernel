#!/bin/bash

echo "------------------------------------------------------"
echo "---             RAD-KERNEL-BUILD-SCRIPT            ---"
echo "------------------------------------------------------"
	
JOBS=$(nproc)
KERNELDIR=$(pwd)
export USE_CCACHE=1
export CCACHE_DIR=~/.ccache

export VERSION=a42xq
export CLEAN=yes
export DEVICE=a42xq

     echo "Cleaning Source!"
export CLEAN=yes

export LOCALVERSION=-RAD-${VERSION}-${DATE}-AOSP

export ARCH=arm64
export PATH="$(pwd)/clang/bin/:$(pwd)/toolchain/bin:${PATH}"
export CROSS_COMPILE=$(pwd)/toolchain/bin/aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export KERNEL_MAKE_ENV="DTC_EXT=$(pwd)/tools/dtc CONFIG_BUILD_ARM64_DT_OVERLAY=y"

	echo "Executing make clean & make mrproper!";
	BUILD_START=$(date +"%s");
	rm -rf out;
	mkdir -p out;
	make O=out clean && make O=out mrproper;

	rm -rf ${KERNELDIR}/out/arch/arm64/boot/Image;
	rm -rf ${KERNELDIR}/out/arch/arm64/boot/a42xq_eur_open.img;
	BUILD_START=$(date +"%s");

	


	
echo "-----------------------------------------"	
echo ....................................
echo ....................................
echo ...""BUILDING KERNEL "".............
echo ....................................
echo ....................................
make O=out a42xq-${DEFCONFIG}_defconfig && script -q ~/Compile.log -c "
make O=out CC=clang -j${JOBS}"

if [ ! -e ${KERNELDIR}/RAD/logs ]; then
		mkdir ${KERNELDIR}/RAD/logs;
		
fi;
	

		mkdir ${KERNELDIR}/RAD/Releases;
		
	
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


