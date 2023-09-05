#!/usr/bin/env bash
#set -e

# Export Vars
export PWDIR=$(pwd)
export KERNELDIR=$PWDIR/13
export ANYKERNELDIR=$PWDIR/Anykernel3
export KERNEL_DEFCONFIG=vendor/sweet-perf_defconfig
export BUILD_TIME=$(date +"%Y%m%d-%H%M%S")
export ARCH=arm64
export SUBARCH=arm64
export ZIPNAME=XYZABC
export DEVICE=sweet

export BUILD_TYPE=canary
export PRERELEASE=true
echo "Build Type: Canary"
if [ x${1} == xstable ]; then
    export BUILD_TYPE=stable
    export PRERELEASE=false
    export COMPILER=clang
    echo "Build Type: Stable"
fi

if [ x${2} == xfloral ]; then
    export DEVICE=floral
    export COMPILER=gcc
    export KERNEL_DEFCONFIG=floral_defconfig
fi

echo "Build Device: ${DEVICE}"

if [ x$BUILD_TYPE == xstable ]; then
    export BUILD_VARIANTS=(OSS MIUI OSS-KSU MIUI-KSU)
fi

if [ x$BUILD_TYPE == xcanary ]; then
#    export BUILD_VARIANTS=(OSS MIUI OSS-135HZ MIUI-135HZ)
    export BUILD_VARIANTS=(OSS MIUI)
fi

if [ x$DEVICE == xfloral ]; then
    export BUILD_VARIANTS=(OSS)
fi

# Clone kernel
echo -e "$green << cloning kernel >> \n $white"
if [ x$DEVICE == xsweet ]; then
    git clone -j$(nproc --all) \
              --single-branch \
              -b android \
              https://${GH_TOKEN}@github.com/DoraCore-Projects/android_kernel_xiaomi_sweet.git \
              $KERNELDIR > /dev/null 2>&1
    cd $KERNELDIR
fi

if [ x$DEVICE == xfloral ]; then
    git clone -j$(nproc --all) \
              --single-branch \
              -b 11.0.0-sultan \
              https://${GH_TOKEN}@github.com/DoraCore-Projects/android_kernel_xiaomi_floral.git \
              $KERNELDIR > /dev/null 2>&1
    cd $KERNELDIR
fi

# Cleanup
rm -rf $PWDIR/ZIPOUT
rm -rf $KERNELDIR/out

# Update Submodules
git submodule init
git submodule update
git submodule update --recursive --remote
git add -vAf
git commit -sm "Kernel: Latest commit, KernelSU and KProfiles"

export commit_sha=$(git rev-parse HEAD)
echo -e "Latest commit is: "${commit_sha}

sleep 5

mkdir -p $PWDIR/ZIPOUT

# Tool Chain
if [ x$DEVICE == xsweet ]; then
    echo -e "$green << cloning gcc >> \n $white"
    # git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 "$PWDIR"/gcc64 > /dev/null 2>&1
    # git clone --depth=1 https://github.com/mvaisakh/gcc-arm "$PWDIR"/gcc32 > /dev/null 2>&1
    git clone -b master --single-branch --depth=1 https://github.com/radcolor/aarch64-linux-gnu.git "$PWDIR"/gcc64 > /dev/null 2>&1
    git clone -b master --single-branch --depth=1 https://github.com/radcolor/arm-linux-gnueabi.git"$PWDIR"/gcc32 > /dev/null 2>&1
    # export CROSS_COMPILE="$PWDIR"/gcc64/bin/aarch64-elf-
    # export CROSS_COMPILE_ARM32="$PWDIR"/gcc32/bin/arm-eabi-
    export CROSS_COMPILE="$PWDIR"/gcc64/bin/aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32="$PWDIR"/gcc32/bin/arm-linux-gnueabi-
    export PATH="$PWDIR/gcc64/bin:$PWDIR/gcc32/bin:$PATH"
    export KBUILD_COMPILER_STRING=$("$PWDIR"/gcc64/bin/aarch64-linux-gnu-gcc --version | head -n 1)
fi

# Clang
echo -e "$green << cloning clang >> \n $white"
git clone -b 15 --depth=1 https://gitlab.com/PixelOS-Devices/playgroundtc.git "$PWDIR"/clang > /dev/null 2>&1
# git clone -b master --single-branch --depth="1" https://gitlab.com/GhostMaster69-dev/cosmic-clang.git "$PWDIR"/clang > /dev/null 2>&1
export PATH="$PWDIR/clang/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$PWDIR"/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

# Speed up build process
MAKE="./makeparallel"
BUILD_START=$(date +"%s")
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

start_build() {
    if [[ "${COMPILER}" = gcc ]]; then
        cd ${PWDIR}
        pwd
        echo "**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****"
        echo -e "$blue***********************************************"
        echo "          BUILDING KERNEL          "
        echo -e "***********************************************$nocol"
        if [ ! -d "${PWDIR}/gcc64" ]; then
            wget -O "${PWDIR}"/64.zip https://github.com/mvaisakh/gcc-arm64/archive/1a4410a4cf49c78ab83197fdad1d2621760bdc73.zip
            unzip "${PWDIR}"/64.zip
            mv "${PWDIR}"/gcc-arm64-1a4410a4cf49c78ab83197fdad1d2621760bdc73 "${PWDIR}"/gcc64
        fi

        if [ ! -d "${PWDIR}/gcc32" ]; then
            wget -O "${PWDIR}"/32.zip https://github.com/mvaisakh/gcc-arm/archive/c8b46a6ab60d998b5efa1d5fb6aa34af35a95bad.zip
            unzip "${PWDIR}"/32.zip
            mv "${PWDIR}"/gcc-arm-c8b46a6ab60d998b5efa1d5fb6aa34af35a95bad "${PWDIR}"/gcc32
        fi

        if [ ! -f "${PWDIR}/ld.lld" ]; then
            wget https://gitlab.com/zlatanr/dora-clang-1/-/raw/master/bin/lld -O "${PWDIR}"/ld.lld && chmod +x ld.lld
        fi

        export KBUILD_COMPILER_STRING=$("${PWDIR}"/gcc64/bin/aarch64-elf-gcc --version | head -n 1)
        export PATH="${PWDIR}"/gcc32/bin:"${PWDIR}"/gcc64/bin:/usr/bin/:${PATH}

        cd ${KERNELDIR}

        make O=out $KERNEL_DEFCONFIG

        MAKEFLAGS+=(
            ARCH=arm64
            O=out
            CROSS_COMPILE=aarch64-elf-
            CROSS_COMPILE_ARM32=arm-eabi-
            LD="${PWDIR}"/ld.lld
            AR=llvm-ar
            OBJDUMP=llvm-objdump
            STRIP=llvm-strip
            CC=aarch64-elf-gcc
        )

        make -j$(nproc --all) "${MAKEFLAGS[@]}" Image.lz4 2>&1 | tee log.txt
        make -j$(nproc --all) "${MAKEFLAGS[@]}" dtbs dtbo.img 2>&1 | tee log.txt

    elif [[ "${COMPILER}" = clang ]]; then
        echo "**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****"
        echo -e "$blue***********************************************"
        echo "          BUILDING KERNEL          "
        echo -e "***********************************************$nocol"
        make $KERNEL_DEFCONFIG O=out CC=clang
        make -j$(nproc --all) O=out CC=clang \
            ARCH=arm64 \
            LLVM=1 \
            LLVM_IAS=1 \
            AR=llvm-ar \
            NM=llvm-nm \
            LD=ld.lld \
            OBJCOPY=llvm-objcopy \
            OBJDUMP=llvm-objdump \
            STRIP=llvm-strip \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE="$PWDIR"/gcc64/bin/aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32="$PWDIR"/gcc32/bin/arm-linux-gnueabi- \
            2>&1 | tee error.log
    fi

    if [ x$DEVICE == xsweet ]; then
        find $KERNELDIR/out/arch/arm64/boot/dts/ -name '*.dtb' -exec cat {} + > $KERNELDIR/out/arch/arm64/boot/dtb

        # export IMGDTB=$KERNELDIR/out/arch/arm64/boot/Image.gz-dtb
        export IMG=$KERNELDIR/out/arch/arm64/boot/Image.gz
        export DTBO=$KERNELDIR/out/arch/arm64/boot/dtbo.img
        export DTB=$KERNELDIR/out/arch/arm64/boot/dtb
    fi

    if [ x$DEVICE == xfloral ]; then
        export IMG=$KERNELDIR/out/arch/arm64/boot/Image.lz4
        export DTBO=$KERNELDIR/out/arch/arm64/boot/dtbo.img
        export DTB=$KERNELDIR/out/arch/arm64/boot/dtb

        git clone -b "floral/11.0.0-sultan" https://github.com/kerneltoast/AnyKernel3.git $ANYKERNELDIR

        cp -r $IMG $ANYKERNELDIR/
        cp -r $DTBO $ANYKERNELDIR/
        cp -r $DTB $ANYKERNELDIR/

        cd $ANYKERNELDIR/

        zip -r9 "$ZIPNAME" * -x '*.git*' README.md *placeholder
    fi

    if [ -f $IMG ] && [ -f $DTBO ] && [ -f $DTB ]; then
        echo "------ Finishing Build ------"
        if [ x$DEVICE == xsweet ]; then
            git clone -b DoraCore --single-branch https://${GH_TOKEN}@github.com/DoraCore-Projects/Anykernel3.git $ANYKERNELDIR
            zip -rv9 $KERNELDIR/Prebuilt-${BUILD_VARIANT}-${DEVICE}.zip $KERNELDIR/out/arch/arm64/boot
            cp -r $IMG $ANYKERNELDIR/
            cp -r $DTBO $ANYKERNELDIR/
            cp -r $DTB $ANYKERNELDIR/
            cd $ANYKERNELDIR
            sed -i "s/is_slot_device=0/is_slot_device=auto/g" anykernel.sh
            zip -r9 "$ZIPNAME" * -x '*.git*' README.md *placeholder
        fi
    else
        echo -e "\n Compilation Failed!"
    fi

    cd -
    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
    echo ""
    echo -e "$ZIPNAME is ready!"
    mv $ANYKERNELDIR/$ZIPNAME $PWDIR/ZIPOUT/
    if [ x$DEVICE == xsweet ]; then
        mv $KERNELDIR/Prebuilt-${BUILD_VARIANT}-${DEVICE}.zip $PWDIR/ZIPOUT/
    fi
    rm -rf $ANYKERNELDIR
    ls $PWDIR/ZIPOUT/
    echo ""
}

generate_message() {
    MSG=$(sed 's/$/\\n/g' ${PWDIR}/Infomation.md | tr -d '\n')
}

generate_release_data() {
    cat <<EOF
{
"tag_name":"${BUILD_TIME}",
"target_commitish":"main",
"name":"${ZIPNAME}",
"body":"$MSG",
"draft":false,
"prerelease":${PRERELEASE},
"generate_release_notes":false
}
EOF
}

create_release() {
    echo "Creating Release"
    generate_message
    url=https://api.github.com/repos/DoraCore-Projects/build-scripts/releases
    upload_url=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: token ${GH_TOKEN}" \
        $url \
        -d "$(generate_release_data)" | jq -r .upload_url | cut -d { -f'1')
}

upload_release_file() {
    command="curl -s -o /dev/null -w '%{http_code}' \
        -H 'Authorization: token ${GH_TOKEN}' \
        -H 'Content-Type: $(file -b --mime-type ${1})' \
        --data-binary @${1} \
        ${upload_url}?name=$(basename ${1})"

    http_code=$(eval $command)
    if [ $http_code == "201" ]; then
        echo "asset $(basename ${1}) uploaded"
    else
        echo "upload failed with code '$http_code'"
        exit 1
    fi
}

for BUILD_VARIANT in ${BUILD_VARIANTS[@]}; do
    git reset --hard ${commit_sha}
    echo "Build Variant: ${BUILD_VARIANT}"
    export ZIPNAME="DoraCore-${BUILD_VARIANT}-${BUILD_TYPE}-${DEVICE}-${BUILD_TIME}.zip"
    if [ x$DEVICE == xfloral ]; then
        export ZIPNAME="DoraCore-${DEVICE}-${BUILD_TIME}.zip"
    fi
    if [ x$BUILD_VARIANT == xMIUI ] && [ x$DEVICE == xsweet ]; then
        git reset --hard ${commit_sha}
        git cherry-pick 370deacbaec3961195d0a9e9a7950e546f075766
    fi
    if [ x$BUILD_VARIANT == xOSS-KSU ] && [ x$DEVICE == xsweet ]; then
        git cherry-pick 7cc9c8e01acf680d1a7f83c90e1eabdf5a11e6fb
    fi
    if [ x$BUILD_VARIANT == xMIUI-KSU ] && [ x$DEVICE == xsweet ]; then
        git cherry-pick 7cc9c8e01acf680d1a7f83c90e1eabdf5a11e6fb
    fi
    if [ x$BUILD_TYPE == xcanary ] && [ x$DEVICE == xsweet ]; then
        git cherry-pick 7cc9c8e01acf680d1a7f83c90e1eabdf5a11e6fb
    fi
#    if [ x$BUILD_VARIANT == xMIUI-135HZ ]; then
#        git reset --hard ${commit_sha}
#        git cherry-pick 18e95730e4e2cc796674f888dfbced069b69895c
#        git cherry-pick 01e33e9a2272f387614b17c883aee1fc899072bc
#    fi
#    if [ x$BUILD_VARIANT == xOSS-135HZ ]; then
#        git reset --hard ${commit_sha}
#        git cherry-pick 01e33e9a2272f387614b17c883aee1fc899072bc
#    fi
    start_build
done

if [ x$DEVICE == xsweet ]; then
    if [ -f $PWDIR/ZIPOUT/DoraCore-MIUI-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip ] && [ -f $PWDIR/ZIPOUT/DoraCore-OSS-${BUILD_TYPE}-sweet-${BUILD_TIME}.zip ]; then
        # Create Release
        create_release
    else
        echo "Build Failed !!!"
        exit 1
    fi
fi

if [ x$DEVICE == xfloral ]; then
    if [ -f $PWDIR/ZIPOUT/DoraCore-floral-${BUILD_TIME}.zip ]; then
        # Create Release
        create_release
    else
        echo "Build Failed !!!"
        exit 1
    fi
fi

# Upload Release Assets
if [ x$DEVICE == xsweet ]; then
    for BUILD_VARIANT in ${BUILD_VARIANTS[@]}; do
        upload_release_file $PWDIR/ZIPOUT/DoraCore-${BUILD_VARIANT}-${BUILD_TYPE}-${DEVICE}-${BUILD_TIME}.zip
    done
fi

if [ x$DEVICE == xfloral ]; then
    upload_release_file $PWDIR/ZIPOUT/DoraCore-${DEVICE}-${BUILD_TIME}.zip
    # upload_release_file $PWDIR/ZIPOUT/Prebuilt-${BUILD_VARIANT}-${DEVICE}.zip
fi

if [ x$DEVICE == xsweet ]; then
    for BUILD_VARIANT in ${BUILD_VARIANTS[@]}; do
        upload_release_file $PWDIR/ZIPOUT/Prebuilt-${BUILD_VARIANT}-${DEVICE}.zip
    done
fi
