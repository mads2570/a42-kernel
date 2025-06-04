#!/bin/bash

echo "------------------------------------------------------"
echo "---             RAD-KERNEL-BUILD-SCRIPT            ---"
echo "------------------------------------------------------"

DATE=$(date +'%Y%m%d-%H%M')
JOBS=$(nproc)
KERNELDIR=$(pwd)
export USE_CCACHE=1
export CCACHE_DIR=~/.ccache
export DEFCONFIG=a42xq_eur_open;
export AIK_a42xq_PATH=AIK-a42xq;
=======
export DEFCONFIG=a42xq_eur_open_;
export AIK_S8p_PATH=AIK-a42xq;
	
export LOCALVERSION=-RAD-${VERSION}-${DATE}

export ARCH=arm64
export PATH="$(pwd)/clang/bin/:$(pwd)/toolchain/bin:${PATH}"
export CROSS_COMPILE=$(pwd)/toolchain/bin/aarch64-linux-gnu-
export :CLANG_TRIPLE=aarch64-linux-gnu- vendor/a42xq_eur_open_defconfig

if [ "${CLEAN}" == "yes" ]; then
	echo "Executing make clean & make mrproper!";
	BUILD_START=$(date +"%s");
	rm -rf out;
	mkdir -p out;
	make O=out clean && make O=out mrproper;
  elif [ "${CLEAN}" == "no" ]; then
	echo "Initiating Dirty build!";
	BUILD_START=$(date +"%s");
	fi;
	
echo "-----------------------------------------"	

echo "------------------------------------------------------"
echo "---                Building Kernel!                ---"
echo "------------------------------------------------------"
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
        echo ""Making Flashable Zip!""
        echo ""
	rm -rf ${KERNELDIR}/RAD/${AIK_a42xq_PATH}/split_img/boot.img-dt
	rm -rf ${KERNELDIR}/RAD/${AIK_a42xq_PATH}/split_img/boot.img-zImage
	rm -rf ${KERNELDIR}/RAD/${AIK_a42xq_PATH}/image-new.img
else
	echo ""
	echo "Kernel didnt build successfully!"
	echo "No zIMAGE in out dir"
	export BUILD=FAIL
	echo "Copying Logs!"
	rm -rf ${KERNELDIR}/RAD/logs/build_fail-${VERSION}-${DATE}-${DEFCONFIG}.log
	mv ~/Compile.log ${KERNELDIR}/RAD/logs/build_fail-${VERSION}-${DATE}-${DEFCONFIG}.log
fi;

if [ "${BUILD}" == "FAIL" ]; then
	read -p "Do you want to read the logs? (y/n) > " log
fi;

if [ "$log" = "Y" -o "$log" = "y" ]; then
     echo "Opening log!"
     nano ${KERNELDIR}/RAD/logs/build_fail-${VERSION}-${DATE}-${DEFCONFIG}.log
     echo "Exiting!"
     exit 0
  elif [ "$log" = "N" -o "$log" = "n" ]; then
	echo "Exiting!";
	exit 0
fi;

	echo ""
	echo "Copying zImage & dt.img to AIK dir!"
	echo ""
if [ "${DEVICE}" == "a42xq" ]; then
		cp ${KERNELDIR}/out/arch/arm64/boot/Image ${KERNELDIR}/RAD/${AIK_a42xq_PATH}/split_img/boot.img-zImage;
		cp ${KERNELDIR}/out/arch/arm64/boot/dtb_dreamlte.img ${KERNELDIR}/RAD/${AIK_a42xq_PATH}/split_img/boot.img-dt;

	fi;
		
	echo ""
	echo "Zipping up AIK!"
	echo ""
if [ "${DEVICE}" == "a42xq" ]; then
	cd ${KERNELDIR}/RAD/${AIK_a42xq_PATH}
	bash repackimg.sh

	mv image-new.img ${KERNELDIR}/RAD/Flashable/boot_a42.img
	mkdir ${KERNELDIR}/RAD/Releases/${VERSION}
	cd ${KERNELDIR}/RAD/Flashable && zip -r9 RAD-${VERSION}-${DATE}.zip * -x README.md RAD-${VERSION}-${DATE}.zip/
	mv RAD-${VERSION}-${DATE}.zip ${KERNELDIR}/RAD/Releases/${VERSION}/RAD-${VERSION}-${DATE}.zip
    fi;
    
	BUILD_END=$(date +"%s");
	DIFF=$(($BUILD_END - $BUILD_START));
	echo "";
	echo "Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.";
	echo ""
