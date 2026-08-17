#!/bin/bash

set -ex

export CONDA_BUILD_SYSROOT

export PATH="${BUILD_PREFIX}/bin:$PATH"

unset F77 F90

export CC=$(basename "$CC")
export CXX=$(basename "$CXX")
export FC=$(basename "$FC")
export PYTHON=python

if [[ "$target_platform" == "linux-aarch64" ]]; then
  export CROSS_F77_SIZEOF_INTEGER=4
  export CROSS_F77_SIZEOF_REAL=4
  export CROSS_F77_SIZEOF_DOUBLE_PRECISION=8
  export CROSS_F77_SIZEOF_LOGICAL=4
  export CROSS_F77_TRUE_VALUE=1
  export CROSS_F77_FALSE_VALUE=0
  export CROSS_F90_ADDRESS_KIND=8
  export CROSS_F90_OFFSET_KIND=8
  export CROSS_F90_INTEGER_KIND=4
  export CROSS_F90_REAL_MODEL=" 6 , 37"
  export CROSS_F90_DOUBLE_MODEL=" 15 , 307"
fi

export CPPFLAGS="-I$PREFIX/include"
export CFLAGS="-I$PREFIX/include"
export CXXFLAGS="-I$PREFIX/include"
export FFLAGS="-I$PREFIX/include"
export FCFLAGS="-I$PREFIX/include"

# Conditionally add -fallow-argument-mismatch for gfortran >=10
if [[ "$(uname)" == "Linux" ]] || [[ "$(uname)" == "Darwin" ]]; then
  GFORTRAN_VERSION=$("${FC}" -dumpversion | cut -d. -f1)
  if [[ "${GFORTRAN_VERSION}" -ge 10 ]]; then
    export FFLAGS="${FFLAGS} -fallow-argument-mismatch"
    export FCFLAGS="${FCFLAGS} -fallow-argument-mismatch"
  fi
fi

export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-rpath-link,$PREFIX/lib -Wl,--as-needed"

# Phase 1: UCX
cd ucx

./contrib/configure-release \
    --build="${BUILD}" \
    --host="${HOST}" \
    --prefix="${PREFIX}" \
    --with-sysroot \
    --disable-static \
    --enable-openmp \
    --enable-cma \
    --enable-mt \
    --with-gnu-ld \
    --with-knem=${PREFIX} \
    --with-rdmacm=${PREFIX} \
    --with-verbs=${PREFIX} \
    --with-xpmem=${PREFIX} \
    --enable-stats

make -j${CPU_COUNT}

make install

find "${PREFIX}/lib" -name "libu*.la" -delete

# Phase 2: shs-libfabric (CXI provider for Slingshot)
cd ../shs-libfabric

autoreconf -ivf

./configure --prefix=${PREFIX} \
            --with-sysroot=${CONDA_BUILD_SYSROOT} \
            --enable-cxi \
            --with-cassini-headers=${PREFIX} \
            --with-cxi-uapi-headers=${PREFIX} \
            --with-curl=${PREFIX} \
            --with-json-c=${PREFIX} \
            --with-libnl=${PREFIX} \
            --docdir=$PWD/noinst/doc \
            --mandir=$PWD/noinst/man \
            --disable-lpp \
            --disable-psm3 \
            --disable-opx \
            --disable-efa \
            --disable-static

make -j${CPU_COUNT} src/libfabric.la
make -j${CPU_COUNT} util/fi_info util/fi_pingpong util/fi_strerror util/fi_mon_sampler

make install-exec install-data

# Phase 3: MPICH
cd ../mpich

unset PKG_CONFIG_PATH

# configure balks if F90 is defined
# with a fatal deprecation message pointing to FC
unset F90 F77

export FCFLAGS="$FFLAGS"

# avoid absolute-paths in compilers
export CC=$(basename "$CC")
export CXX=$(basename "$CXX")
export FC=$(basename "$FC")

export MPICHLIB_CPPFLAGS=$CPPFLAGS
unset CPPFLAGS
export MPICHLIB_CFLAGS=$CFLAGS
unset CFLAGS
export MPICHLIB_CXXFLAGS=$CXXFLAGS
unset CXXFLAGS
export MPICHLIB_LDFLAGS=$LDFLAGS
unset LDFLAGS
export MPICHLIB_FFLAGS=$FFLAGS
unset FFLAGS
export MPICHLIB_FCFLAGS=$FCFLAGS
unset FCFLAGS

# set some specific flags that we *do* want recorded in the compilers
# only the bare minimum of prefix-awareness here
export CPPFLAGS="-I$PREFIX/include"
export CFLAGS="-I$PREFIX/include"
export CXXFLAGS="-I$PREFIX/include"
export FFLAGS="-I$PREFIX/include"
export FCFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"

export LIBRARY_PATH="$PREFIX/lib"

./configure --prefix=$PREFIX \
            --with-sysroot=${CONDA_BUILD_SYSROOT} \
            --disable-doc \
            --disable-dependency-tracking \
            --enable-cxx \
            --enable-fortran \
            --enable-f08 \
            --enable-romio \
            --with-device=ch4:ucx,ofi \
            --with-libfabric=$PREFIX \
            --with-ucx=$PREFIX \
            --with-xpmem=$PREFIX \
            --with-hwloc=$PREFIX \
            --with-pm=hydra:gforker \
            --with-wrapper-dl-type=none \
            --disable-static \
            || (cat config.log; exit 1)

make -j"${CPU_COUNT:-1}"

make install

# Phase 4: OSU Micro-Benchmarks
cd ../omb

export PATH="${PREFIX}/bin:$PATH"

./configure CC=mpicc CXX=mpicxx

make -j"${CPU_COUNT:-1}"

make install
