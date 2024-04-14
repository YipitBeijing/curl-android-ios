#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

XCODE=$(xcode-select -p)
if [ ! -d "$XCODE" ]; then
	echo "You have to install Xcode and the command line tools first"
	exit 1
fi

REL_SCRIPT_PATH="$(dirname $0)"
SCRIPTPATH=$(realpath "$REL_SCRIPT_PATH")
CURLPATH="$SCRIPTPATH/../curl"

PWD=$(pwd)
cd "$CURLPATH"

if [ ! -x "$CURLPATH/configure" ]; then
	echo "Curl needs external tools to be compiled"
	echo "Make sure you have autoconf, automake and libtool installed"

	./buildconf

	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the buildconf program"
		cd "$PWD"
		exit $EXITCODE
	fi
fi

# export CC="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
DESTDIR="$SCRIPTPATH/../prebuilt-with-ssl/iOS"

export IPHONEOS_DEPLOYMENT_TARGET="10"
ARCHS=(armv7 armv7s arm64 arm64 x86_64)
HOSTS=(armv7 armv7s arm arm64 x86_64)
PLATFORMS=(iPhoneOS iPhoneOS iPhoneOS iPhoneSimulator iPhoneSimulator)
SDK=(iphoneos iphoneos iphoneos iphonesimulator iphonesimulator)

#Build for all the architectures
for (( i=0; i<${#ARCHS[@]}; i++ )); do
	ARCH=${ARCHS[$i]}
	BITCODE_FLAGS="-fembed-bitcode"
	SYSROOT=$(xcrun --sdk ${SDK[$i]} --show-sdk-path)
	TARGET="$ARCH-apple-ios"
	if [ "${PLATFORMS[$i]}" = "iPhoneSimulator" ]; then
		TARGET="$ARCH-apple-ios-simulator"
		BITCODE_FLAGS=""
		export CPPFLAGS="-isysroot ${SYSROOT} -D__IPHONE_OS_VERSION_MIN_REQUIRED=${IPHONEOS_DEPLOYMENT_TARGET%%.*}0000"
	fi
	export CFLAGS="-target $TARGET -arch $ARCH -pipe -Os -gdwarf-2 -isysroot ${SYSROOT} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET} $BITCODE_FLAGS -Werror=partial-availability"
	export LDFLAGS="-arch $ARCH -isysroot ${SYSROOT}"

	cd "$CURLPATH"
	./configure	--host="${HOSTS[$i]}-apple-darwin" \
			--with-darwinssl \
			--enable-static \
			--disable-shared \
			--enable-threaded-resolver \
			--disable-verbose \
			--enable-ipv6
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the cURL configure program"
		cd "$PWD"
		exit $EXITCODE
	fi

	make -j $(sysctl -n hw.logicalcpu_max)
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the make program"
		cd "$PWD"
		exit $EXITCODE
	fi
	mkdir -p "$DESTDIR/${PLATFORMS[$i]}_$ARCH"
	cp "$CURLPATH/lib/.libs/libcurl.a" "$DESTDIR/${PLATFORMS[$i]}_$ARCH/"
	make clean
done

git checkout $CURLPATH
 
#Copying cURL headers
if [ -d "$DESTDIR/include" ]; then
	echo "Cleaning headers"
	rm -rf "$DESTDIR/include"
fi
cp -R "$CURLPATH/include" "$DESTDIR/"
rm "$DESTDIR/include/curl/.gitignore"

#Build universal lib for each platform
cd "$DESTDIR"
mkdir -p iPhoneOS_universal
mkdir -p iPhoneSimulator_universal
rm -rf iPhoneOS_universal/libcurl.a
rm -rf iPhoneSimulator_universal/libcurl.a
lipo -create iPhoneOS_*/libcurl.a -output iPhoneOS_universal/libcurl.a
lipo -create iPhoneSimulator_*/libcurl.a -output iPhoneSimulator_universal/libcurl.a

#Build universal xcframework with all the archs in it
rm -rf curl.xcframework
xcodebuild -create-xcframework \
	-library iPhoneOS_universal/libcurl.a \
	-library iPhoneSimulator_universal/libcurl.a \
	-output curl.xcframework\

echo "clean"
rm -rf iPhoneOS_*
rm -rf iPhoneSimulator_*

cd "$PWD"