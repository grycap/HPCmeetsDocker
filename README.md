# Create the HPCmeetsDocker image

First we get HPCmeetsDocker from git:

```bash
git clone https://github.com/grycap/HPCmeetsDocker
``` 

Now we create a container and push the files needed to create the installation

```bash
lxc launch local:ubuntu:16.04 HPCmD -p default -p docker
lxc exec HPCmD -- mkdir -p /opt/HPCmeetsDocker/install 
tar c -C ./HPCmeetsDocker/install/ . | lxc exec HPCmD -- tar xf - -C /opt/HPCmeetsDocker/install
```

Enter the container and execute the installation

```bash
lxc exec HPCmD -- bash -c 'cd /opt/HPCmeetsDocker/install
./01install-docker
./02install-munge
./03compile-slurm
./04install-mpi-python
'
```

Now stop the container and publish the golden image

```bash
lxc stop HPCmD
lxc publish HPCmD local: --alias HPCmD:0.1
```

# Using with MCC

I create a profile for mcc and I make it privileged for my purposes

```bash
lxc profile create HPCmD
lxc profile device add HPCmD aadisable disk path=/sys/module/apparmor/parameters/enabled source=/dev/null
lxc profile set HPCmD security.nesting true
lxc profile set HPCmD linux.kernel_modules 'overlay, nf_nat'
lxc profile set HPCmD security.privileged true
```

You can issue the whole profile, instead:

```bash
cat <<\EOF | lxc profile edit HPCmD
name: HPCmD
config:
  linux.kernel_modules: overlay, nf_nat
  security.nesting: "true"
  security.privileged: "true"
description: Profile for HPCmD, that supports Docker inside the containers and is privileged (it is a copy of the docker profile, setting the privilege to true)
devices:
  aadisable:
    path: /sys/module/apparmor/parameters/enabled
    source: /dev/null
    type: disk
EOF
```

And then I use to launch the cluster using [MCC](https://github.com/grycap/mcc).

```bash
MCC_LXC_LAUNCH_OPTS="-p HPCmD" mcc --verbose create --front-end-image local:HPCmD:0.1 --context-folder ./HPCmeetsDocker/ -n 2 -e -d home
```

And now I have a cluster that consists of 2 computing nodes, with a shared home folder. The computing nodes have docker and slurm installed, and a single user called _ubuntu_ that is able to launch docker containers.

# Testing the cluster

## OpenFOAM

First grab the openfoam image (can be done as root or as any other user)

```bash
docker pull openfoam/openfoam4-paraview50
ssh node1 docker pull openfoam/openfoam4-paraview50
ssh node2 docker pull openfoam/openfoam4-paraview50
```
Then, as a user, we create a script named ```job.sh``` that we will use to run openfoam in slurm

```bash
#!/bin/bash
#
#SBATCH --ntasks=1
#SBATCH --time=10:00
#SBATCH --mem-per-cpu=1

srun docker run --rm --entrypoint '/bin/bash' -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home/ubuntu:/home/openfoam -u $(id -u):$(id -g) openfoam/openfoam4-paraview50 -c '. /opt/openfoam4/etc/bashrc
mkdir -p $FOAM_RUN 
run 
cp -r $FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity . 
cd cavity 
blockMesh 
icoFoam'
```

If we had our folder with our OpenFOAM case, we could change that ```job.sh``` command by the next fragment

```bash
#!/bin/bash
#
#SBATCH --ntasks=1
#SBATCH --time=10:00
#SBATCH --mem-per-cpu=1

cd cavity
srun docker run --rm --entrypoint '/bin/bash' -w "$(pwd)" -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home:/home -u $(id -u):$(id -g) openfoam/openfoam4-paraview50 -c '. /opt/openfoam4/etc/bashrc
blockMesh 
icoFoam'
```

Then we could submit the job to slurm:

```bash
sbatch job.sh
```

# Using MPI

## Ensuring that MPI is running

First of all, you must ensure that you are able to run MPI. In order to make it, a basic set-up is included here:

Installing OpenMPI:
```bash
apt-get install -y openmpi-bin openssh-client openssh-server libopenmpi-dev python python-pip
pip install --upgrade pip mpi4py
```

Preparing the passwordless ssh access. We assume that the /home folder is shared between the different hosts
```bash
su - ubuntu
ssh-keygen
cat .ssh/id_rsa.pub >> .ssh/authorized_keys
chmod 400 .ssh/authorized_keys
cat > .ssh/config << EOF
Host node*
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
LogLevel QUIET
EOF
```

Running a basic test in python:
```bash
cat > mpi_hello.py <<\EOF
from mpi4py import MPI
comm = MPI.COMM_WORLD
rank = comm.Get_rank()
print "hello world from process ", rank
import socket
print(socket.gethostname())
EOF

mpirun -np 2 -H node1,node2 python mpi_hello.py
```

And this is our basic setup for a MPI platform.
