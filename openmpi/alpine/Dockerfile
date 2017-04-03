#
# HPCmeetsDocker - Integrating Docker containers with HPC batch queue systems
# https://github.com/grycap/HPCmeetsDocker
#
# Copyright (C) GRyCAP - I3M - UPV
# Developed by Carlos A. caralla@upv.es
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
FROM alpine
# We need some patches to be able to compile OpenMPI 2.1 in Alpine
COPY cma.h-patch pmix_common.h-patch /tmp/
# Now we make a "oneliner" compilation of OpenMPI in order to reduce the image of the Docker image
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
    rm $(find  /usr/lib/python2.7/ -name '*.pyo') &&\
    rm -f /var/cache/apk/* &&\
    apk del g++ openssl perl make --purge