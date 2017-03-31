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

FROM ubuntu
MAINTAINER Carlos de Alfonso <caralla@upv.es>

# First we install the python runtime and python pip, to be able to run mpi4py based applications.
# We also install the openssh server (as it is used to launch the MPI daemons using openmpi),
# and the OpenMPI libraries 
RUN apt-get update && apt-get -y install python python-pip \
        libopenmpi-dev \
        openssh-server

# Here we install the mpi4py runtime and a scientific library that we'll use to run the benchmarks
RUN pip install --upgrade pip && pip install mpi4py numpy
RUN apt-get install -y libblas3
RUN apt-get install -y libgfortran3