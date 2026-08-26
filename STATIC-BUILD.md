# Fully static build

AAC/ADTS and MP3 support are implemented by Icecast's built-in MPEG frame
parser; Icecast does not decode these streams, so no AAC or MP3 codec library
is needed.  TLS uses OpenSSL and URL authentication, relays, and YP use
libcurl.

The reproducible path is a musl binary built in Alpine Linux 3.23:

```sh
docker build -f Dockerfile.static --target artifact -o static-out .
file static-out/icecast
readelf -d static-out/icecast
```

The output is `static-out/icecast`.  The build script rejects an executable
with an ELF interpreter or any `DT_NEEDED` dynamic-library entry, and also
checks that OpenSSL, curl authentication, AAC, and MP3 support were enabled.

Podman supports the same command.  On an Alpine 3.23 host, install the packages
listed in `Dockerfile.static` and run `./build-static.sh` directly.  Other
distributions work only when static archives for every dependency reported by
the following command are installed:

```sh
pkg-config --static --libs libxslt vorbis libcurl openssl
```

Using musl avoids the runtime DNS/NSS module caveats of a statically linked
glibc executable.  CA certificates are deliberately not embedded in the
binary; when verifying HTTPS peers, configure Icecast/OpenSSL to use a CA file
present on the target system.
