#!/bin/sh
set -eu

show_config_log_on_error()
{
    status=$?
    if test "$status" -ne 0 && test -f config.log; then
        echo "----- config.log (build failure) -----" >&2
        grep -nE 'conftest|undefined reference|cannot find|error:' config.log | tail -n 100 >&2 || true
        tail -n 200 config.log >&2
    fi
    exit "$status"
}
trap show_config_log_on_error EXIT

# Build Icecast against static archives.  pkg-config's --static output is
# important: it includes libraries used privately by libcurl and libxslt.
for tool in autoreconf pkg-config readelf; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: $tool is required" >&2
        exit 1
    fi
done

static_modules="libxslt vorbis libcurl openssl"
if ! pkg-config --exists $static_modules; then
    echo "error: development files for $static_modules are required" >&2
    exit 1
fi

static_libs=$(pkg-config --static --libs $static_modules)
static_cflags=$(pkg-config --cflags $static_modules)
user_ldflags=${LDFLAGS-}

autoreconf -fi

# Supplying the closure in LIBS puts it after all Icecast objects and internal
# archives, which is the ordering required by traditional static linkers.
CPPFLAGS="${CPPFLAGS-} $static_cflags -DLIBXML_STATIC -DCURL_STATICLIB" \
CFLAGS="${CFLAGS--O2}" \
LDFLAGS="$user_ldflags -static" \
LIBS="${LIBS-} $static_libs" \
    ./configure --disable-shared --enable-static "$@"

make clean
# Libtool consumes -static to mean "prefer static archives".  -all-static is
# required at the program link step to also omit the ELF interpreter.
make V=1 LDFLAGS="$user_ldflags -all-static"

binary=src/icecast
if readelf -l "$binary" | grep -q 'Requesting program interpreter'; then
    echo "error: $binary has a dynamic program interpreter" >&2
    exit 1
fi
if readelf -d "$binary" 2>/dev/null | grep -q '(NEEDED)'; then
    echo "error: $binary has dynamic dependencies" >&2
    exit 1
fi

# Verify the requested compile-time features as well as the ELF result.
for feature in HAVE_OPENSSL HAVE_CURL HAVE_AUTH_URL; do
    if ! grep -Eq "^#define $feature 1$" config.h; then
        echo "error: $feature was not enabled" >&2
        exit 1
    fi
done
if ! grep -q 'FORMAT_TYPE_AAC' src/format.h || ! grep -q 'FORMAT_TYPE_MPEG' src/format.h; then
    echo "error: built-in AAC/MP3 stream support is missing" >&2
    exit 1
fi

echo "$binary is fully static and has TLS, curl, AAC, and MP3 support"
file "$binary" 2>/dev/null || true
trap - EXIT
