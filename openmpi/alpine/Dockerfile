FROM alpine
COPY cma.h-patch pmix_common.h-patch /tmp/
RUN apk update && \
    apk add openssl g++ bash perl make && \
    wget https://www.open-mpi.org/software/ompi/v2.1/downloads/openmpi-2.1.0.tar.gz && \
tar xfz openmpi-2.1.0.tar.gz && \
cd openmpi-2.1.0/  && \
patch opal/mca/pmix/pmix112/pmix/include/pmix/pmix_common.h < /tmp/pmix_common.h-patch && \
patch opal/include/opal/sys/cma.h < /tmp/cma.h-patch && \
mkdir build  && \
cd build  && \
../configure  && \
make all install && \
cd ../.. && \
rm -rf openmpi-2.1.0 &&\
rm -f openmpi-2.1.0.tar.gz &&\
apk del g++ openssl perl make --purge

RUN apk add python py-pip g++ python-dev && pip install --upgrade pip && pip install mpi4py && apk del g++ py-pip python-dev --purge
