#!/bin/bash

set -ex

export CONDA_BUILD_SYSROOT

export PATH="${BUILD_PREFIX}/bin:$PATH"

# avoid absolute-paths in compilers
export CC=$(basename "$CC")
export CXX=$(basename "$CXX")
export FC=$(basename "$FC")
export PYTHON=python

unset F77 F90

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

export CPPFLAGS="-I${PREFIX}/include"
export CFLAGS="-I${PREFIX}/include"
export CXXFLAGS="-I${PREFIX}/include"
export FFLAGS="-I${PREFIX}/include"
export FCFLAGS="-I${PREFIX}/include"
export LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,--as-needed"

# gfortran >=10 needs -fallow-argument-mismatch
GFORTRAN_VERSION=$("${FC}" -dumpversion 2>/dev/null | cut -d. -f1)
if [[ "${GFORTRAN_VERSION:-0}" -ge 10 ]]; then
  export FFLAGS="${FFLAGS} -fallow-argument-mismatch"
  export FCFLAGS="${FCFLAGS} -fallow-argument-mismatch"
fi

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
unset F90 F77

# MPICH records CPPFLAGS/CFLAGS/etc into wrapper scripts (mpicc, mpicxx...).
# MPICHLIB_* overrides what goes into the wrappers.
# Here we want the same flags in both build and wrappers, except LDFLAGS
# where wrappers don't need -rpath-link and --as-needed.
export MPICHLIB_LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
export LIBRARY_PATH="${PREFIX}/lib"

./configure --prefix=${PREFIX} \
            --with-sysroot=${CONDA_BUILD_SYSROOT} \
            --disable-doc \
            --disable-dependency-tracking \
            --disable-option-checking \
            --enable-cxx \
            --enable-fortran=all \
            --enable-f08 \
            --enable-romio \
            --enable-nemesis-shm-collectives \
            --with-device=ch4:ucx,ofi \
            --with-libfabric=${PREFIX} \
            --with-libfabric-include=${PREFIX}/include \
            --with-libfabric-lib=${PREFIX}/lib \
            --with-ucx=${PREFIX} \
            --with-xpmem=${PREFIX} \
            --with-xpmem-include=${PREFIX}/include \
            --with-xpmem-lib=${PREFIX}/lib \
            --with-hwloc=${PREFIX} \
            --with-pm=hydra:gforker \
            --with-wrapper-dl-type=none \
            --with-dl-type=none \
            --disable-static \
            || (cat config.log; exit 1)

make -j${CPU_COUNT}
make install

# Phase 4: OSU Micro-Benchmarks
cd ../omb

export PATH="${PREFIX}/bin:$PATH"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="${PREFIX}/lib"

./configure --prefix=${PREFIX} \
            --disable-dependency-tracking \
            --disable-static \
            CC=mpicc CXX=mpicxx

make -j${CPU_COUNT}
make install
