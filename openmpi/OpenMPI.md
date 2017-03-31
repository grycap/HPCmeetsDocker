# Docker and OpenMPI

I have one cluster that is composed by 3 nodes: node0, node1 and node2. Node0 is the front-end and it has a shared /home filesystem and a user (ubuntu) that has the passwordless ssh access configured.

I'm trying to run containerized workloads using OpenMPI. The idea is to issue a command like

```bash
mpirun -H node1,node2 app
```

and ```app``` is ran inside containers, and the different instances of the applications are able to communicate to each other using the MPI library (the OpenMPI implementation).

## Dockerfile

I need to create a Docker in which the apps are being ran, and that containers has to have the MPI runtime in it. I will use the next Dockerfile for my container image:

```Dockerfile
FROM ubuntu
MAINTAINER Carlos de Alfonso <caralla@upv.es>

# First we install the python runtime and python pip, to be able to run mpi4py based applications.
# We also install the openssh server (as it is used to launch the MPI daemons using openmpi), and the OpenMPI libraries 
RUN apt-get update && apt-get -y install python python-pip \
        openmpi-bin libopenmpi-dev \
        openssh-server

# Now we install the mpi4py runtime and a scientific library that we'll use to run the benchmarks
RUN pip install --upgrade pip && pip install mpi4py && pip install numpy

# Finally we install some libraries that will be needed for our application
RUN apt-get install libgfortran3 libblas3
```

The container image contains the needed applications to run OpenMPI applications, and mpi4py applications (I will use mpi4py because it is very easy to create python mpi applications).

## The OpenMPI workflow

In the OpenMPI workflow, one main node (called the Head Node Processor, HNP) launches an _orte daemon_ and uses _rsh_ to launch other _orte daemons_ in the hosts that are running the application.

In our case, we need that the HNP create some Docker containers in which the _orte daemons_ are started (and the applications are being ran). 

So I will use the _plm_rsh_agent_ parameter of OpenMPI to start the _orte daemons_ in containers in the hosts, instead of just starting the _orte daemons_.

## Running Docker containerized OpenMPI applications

If we simply run the containers in the hosts, they will have an IP address in the range 172.17.0.2/16 (or similar). But there is not a coordinated mechanism to communicate between containers in different hosts, as Docker sets the IP address in a managed way (probably issuing _ifconfig_ or _ip_ commands instead of using DHCP or equivalent mechanisms).

Moreover, every Docker host will start in the same IP (e.g. 172.17.0.2) and that makes that different containers that fall in different hosts will have the same IP address.

The consequence is that the containers will not be able to communicate between them.

Creating an overlay network makes that the communications are routable between different hosts and different containers. 

### The Overlay Network

I create a [docker overlay network](https://luppeng.wordpress.com/2016/05/03/setting-up-an-overlay-network-on-docker-without-swarm/) and then I will try to launch the containers in it, in order to have connectivity between the internal nodes. The HNP does not need to be in the overlay network.

```bash
docker network create -d overlay --subnet=192.168.0.1/24 HPCmD-overlay
```

When we create Docker containers using the overlay network, the containers will have multiple network devices: one for the overlay network and other for the network in Docker (i.e. 172.17.0.2/16 subnet). This is probably because the people in Docker wants that the container has network connectivity to the outern world (using NAT) even if the overlay network does not provide it.

### Starting the containers

Having two interfaces in the containers is a problem for us to run OpenMPI applications as the _orte daemon_ will try to use all the interfaces and, as noticed before, they are not feasible for communication between containers in different Docker hosts. So we need to make sure that only the interface in the overlay network is used.

Once the containers launch the _orte daemons_ in the overlay network they inform the HNP about the endpoint of _orte_ (in the overlay network) and these endpoints are sent to the other _orte daemons_ to be able to connect between them as they are in the overlay network.

**Note:** The IP of the HNP is routable by the Docker containers through the 172.17.0.2/16 natted address (that is why the HNP does not need to run in a container).

Now that we know all the constraints, I am ready to create a _plm_rsh_agent_, with the following content. It will be named _HPCmD_plm_rsh_agent_:

```bash
#!/bin/bash
HPCmD_DOCKERIMAGE=hpcmd-ubuntu-openmpi
HPCmD_DOCKEROVERLAYNET=HPCmD-overlay
DOCKER_OPTS="-v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home:/home -u $(id -u):$(id -g) -w $(pwd)"
OMPI_OPTS="-mca oob_tcp_if_include eth0 -mca btl_tcp_if_include eth0"
HOST=$1
shift
set -x
ssh $HOST docker run $DOCKER_OPTS --rm --net $HPCmD_DOCKEROVERLAYNET $HPCmD_DOCKERIMAGE "$@" $OMPI_OPTS
```

The scripts _ssh_ the node that is suposed to run the job and creates a container in it, executing the _orte daemon_, and making that only the _eth0_ interface is used for communication.

Using this script, we can issue the next command in order to execute MPI Docker containerized applications.

```bash
mpirun -mca plm_rsh_agent HPCmD_plm_rsh_agent -n 2 -H node1,node2 python mpi_hello.py
+ ssh node2 docker run -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home:/home -u 1000:1000 -w /home/ubuntu --rm --net HPCmD-overlay hpcmd-ubuntu-openmpi ' orted' --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"2987261952"' -mca orte_ess_vpid 2 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"2987261952.0;tcp://10.153.72.131,172.17.0.1,172.18.0.1:45957"' --tree-spawn -mca plm_rsh_agent '"HPCmD_plm_rsh_agent"' -mca plm '"rsh"' --tree-spawn -mca oob_tcp_if_include eth0 -mca btl_tcp_if_include eth0
+ ssh node1 docker run -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home:/home -u 1000:1000 -w /home/ubuntu --rm --net HPCmD-overlay hpcmd-ubuntu-openmpi ' orted' --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"2987261952"' -mca orte_ess_vpid 1 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"2987261952.0;tcp://10.153.72.131,172.17.0.1,172.18.0.1:45957"' --tree-spawn -mca plm_rsh_agent '"HPCmD_plm_rsh_agent"' -mca plm '"rsh"' --tree-spawn -mca oob_tcp_if_include eth0 -mca btl_tcp_if_include eth0
hello world from process  1
hello world from process  0
a06f56d1d3f9
cc7013de26ff
```

And now we are ready to try more complex applications such as the next one (t3.py):

```python
import numpy
from mpi4py import MPI
comm = MPI.COMM_WORLD
rank = comm.Get_rank()

randNum = numpy.zeros(1)

if rank == 1:
    randNum = numpy.random.random_sample(1)
    print "Process", rank, "drew the number", randNum[0]
    comm.Send(randNum, dest=0)

if rank == 0:
    print "Process", rank, "before receiving has the number", randNum[0]
    comm.Recv(randNum, source=1)
    print "Process", rank, "received the number", randNum[0]
```

If we run it, we'll see that it is properly running

```bash
$ mpirun -mca plm_rsh_agent HPCmD_plm_rsh_agent -n 2 -H node1,node2 python t3.py 
+ ssh node1 docker run -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home:/home -u 1000:1000 -w /home/ubuntu --rm --net HPCmD-overlay hpcmd-ubuntu-openmpi ' orted' --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"3032219648"' -mca orte_ess_vpid 1 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"3032219648.0;tcp://10.153.72.131,172.17.0.1,172.18.0.1:47961"' --tree-spawn -mca plm_rsh_agent '"HPCmD_plm_rsh_agent"' -mca plm '"rsh"' --tree-spawn -mca oob_tcp_if_include eth0 -mca btl_tcp_if_include eth0
+ ssh node2 docker run -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home:/home -u 1000:1000 -w /home/ubuntu --rm --net HPCmD-overlay hpcmd-ubuntu-openmpi ' orted' --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"3032219648"' -mca orte_ess_vpid 2 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"3032219648.0;tcp://10.153.72.131,172.17.0.1,172.18.0.1:47961"' --tree-spawn -mca plm_rsh_agent '"HPCmD_plm_rsh_agent"' -mca plm '"rsh"' --tree-spawn -mca oob_tcp_if_include eth0 -mca btl_tcp_if_include eth0
Process 1 drew the number 0.822003205098
Process 0 before receiving has the number 0.0
Process 0 received the number 0.822003205098
```

Up to now, I have left the -x flag, in order to see that everything is properly working. From now on, I am removing that flag.

### Launching Benchmarks

In order to validate my solution, I will try several benchmarks:

- Some [mpi4py examples](https://github.com/jbornschein/mpi4py-examples).
- High-Performance Linpack Benchmark for Distributed-Memory Computers ([HPL](http://www.netlib.org/benchmark/hpl/)).
- NAS Parallel Benchmark ([NPL](https://www.nas.nasa.gov/publications/npb.html))

We will have our script in _/opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent_. And we need that this script is available for the containers (in order to avoid displayin annoying errors), so we are addind the fragment ```-v /opt/HPCmD:/opt/HPCmD:ro``` to the _DOCKER_OPTS_ variable in the script.

#### mpi4py examples

First we download the examples

```bash
$ git clone https://github.com/jbornschein/mpi4py-examples
$ cd mpi4py-examples
```

Now we can run the tests:

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 python 01-hello-world 
Hello! I'm rank 0 from 2 running in total...
Hello! I'm rank 1 from 2 running in total...
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 python 02-broadcast 
------------------------------------------------------------------------------
  Running on 2 cores
 ------------------------------------------------------------------------------
 [00] [ 0.  1.  2.  3.  4.]
[01] [ 0.  1.  2.  3.  4.]
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 python 03-scatter-gather 
------------------------------------------------------------------------------
  Running on 2 cores
 ------------------------------------------------------------------------------
 After Scatter:
 [0] [ 0.  1.  2.  3.]
[1] [ 4.  5.  6.  7.]
After Allgather:
 [0] [  0.   2.   4.   6.   8.  10.  12.  14.]
[1] [  0.   2.   4.   6.   8.  10.  12.  14.]
```

Here we skip some tests because we have not installed the X server in the container... and continue with the other tests.

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 python 07-matrix-vector-product
============================================================================
  Running 2 parallel MPI processes
  20 iterations of size 10000 in  1.05s: 19.04 iterations per second
 ============================================================================
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 python 08-matrix-matrix-product.py 
Creating a 1 x 2 processor grid...
==============================================================================
Computed (serial) 3000 x 3000 x 3000 in    3.08 seconds
 ... expecting parallel computation to take   3.08 seconds
Computed (parallel) 3000 x 3000 x 6000 in          4.09 seconds
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 python 09-task-pull.py 
Master starting with 1 workers
I am a worker with rank 1 on edd97a825fd3.
Sending task 0 to worker 1
Got data from worker 1
Sending task 1 to worker 1
Got data from worker 1
Sending task 2 to worker 1
Got data from worker 1
Sending task 3 to worker 1
Got data from worker 1
Worker 1 exited.
Master finishing
```

We can see that all the tests have been properly executed. You are invited to try them using more processors.

### HPL

First we get and build the HPL benchmark

```bash
$ wget http://www.netlib.org/benchmark/hpl/hpl-2.2.tar.gz
$ tar xfz hpl-2.2.tar.gz
$ ln -s hpl-2.2 hpl
$ cd hpl
$ cp setup/Make.Linux_PII_CBLAS .
```

Now you should edit the Make.Linux_PII_CBLAS file to set it to your particular installation of BLAS, OpenMPI, etc. In particular, I will use the dynamical library of blas (I will install it using ```apt-get install libblas-dev```, set the variable ```LAlib = -lblas```) and set the MPI folder and libraries to the installation of OpenMPI in ubuntu ```MPdir = /usr/lib/openmpi``` and ```MPlib = -lmpi```, and finally set the fortran compiler ```LINKER = /usr/bin/f77``` (it will be needed to be installed with ```apt-get install gfortran```).

Once updated the file, I can compile ```hpl```:

```bash
$ make arch=Linux_PII_CBLAS
...
$ cd bin/Linux_PII_CBLAS/
```

The execution of hpl needs 4 processors. In our case we will use the same nodes (by oversubscribing):

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -H node1,node1,node2,node2 xhp
...
Finished    864 tests with the following results:
            864 tests completed and passed residual checks,
              0 tests completed and failed residual checks,
              0 tests skipped because of illegal input values.
--------------------------------------------------------------------------------

End of Tests.
================================================================================
```

### NPL

We download the NPL from [here](https://www.nas.nasa.gov/publications/npb.html) and unpack it:

```bash
$ wget https://www.nas.nasa.gov/assets/npb/NPB3.3.1.tar.gz
$ tar xfz NPB3.3.1.tar.gz
$ cd NPB3.3.1/NPB3.3-MPI
$ cp config/make.def.template config/make.def
```

Now we need to edit the ```make.def``` file. In my case I will update the following values:

```bash
FMPI_LIB  = -lmpi_mpifh
FMPI_INC = -I/usr/lib/openmpi/include
CMPI_LIB  = -lmpi
CMPI_INC = -I/usr/lib/openmpi/include
```

And we will set the full suite of benchmarks to be compiled (we will compile it for 2 processors and the size S, as we simply want to validate)

```bash
$ cat > config/suite.def << EOF
ft      S       2
mg      S       2
sp      S       2
lu      S       2
bt      S       2
is      S       2
ep      S       2
cg      S       2
dt      S       2
EOF
```

Now we can compile the whole suite of benchmarks, and they will be placed in the ```bin``` folder:

```bash
$ make suite
...
$ ls bin/
cg.S.2  dt.S.x  ep.S.2  ft.S.2  is.S.2  lu.S.2  mg.S.2
```

And now we are ready to test the benchmarks:

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 bin/cg.S.2

 NAS Parallel Benchmarks 3.3 -- CG Benchmark

 Size:       1400
 Iterations:    15
 Number of active processes:     2
 Number of nonzeroes per row:        7
 Eigenvalue shift: .100E+02
...
 Benchmark completed 
 VERIFICATION SUCCESSFUL 
 Zeta is     0.8597177507865E+01
 Error is    0.8264837327252E-15
...
 Please send feedbacks and/or the results of this run to:

 NPB Development Team 
 Internet: npb@nas.nasa.gov
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 6 -H node1,node2,node1,node2,node1,node2 bin/dt.S.x BH


 NAS Parallel Benchmarks 3.3 -- DT Benchmark

-698115160.DT_BH.S: (5,4)
 DT_BH.S L2 Norm = 30892725.000000
 Deviation = 0.000000


 DT_BH.S Benchmark Completed
...
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 bin/ep.S.2 
...
CPU Time =    0.8446
N = 2^   24
No. Gaussian Pairs =      13176389.
Sums =    -3.247834652034487D+03   -6.958407078382574D+03
Counts:
  0       6140517.
  1       5865300.
  2       1100361.
  3         68546.
  4          1648.
  5            17.
  6             0.
  7             0.
  8             0.
  9             0.


 EP Benchmark Completed.
...
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 bin/ft.S.2
 NAS Parallel Benchmarks 3.3 -- FT Benchmark

 No input file inputft.data. Using compiled defaults
 Size                :   64x  64x  64
 Iterations          :              6
 Number of processes :              2
 Processor array     :         1x   2
 Layout type         :             1D
 Initialization time =   3.8540124893188477E-002
 T =    1     Checksum =    5.546087004964D+02    4.845363331978D+02
 T =    2     Checksum =    5.546385409190D+02    4.865304269511D+02
 T =    3     Checksum =    5.546148406171D+02    4.883910722337D+02
 T =    4     Checksum =    5.545423607415D+02    4.901273169046D+02
 T =    5     Checksum =    5.544255039624D+02    4.917475857993D+02
 T =    6     Checksum =    5.542683411903D+02    4.932597244941D+02
 Result verification successful
 class = S


 FT Benchmark Completed.
...
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 bin/is.S.2 


 NAS Parallel Benchmarks 3.3 -- IS Benchmark

 Size:  65536  (class S)
 Iterations:   10
 Number of processes:     2


 IS Benchmark Completed
...
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 bin/lu.S.2 

 NAS Parallel Benchmarks 3.3 -- LU Benchmark

 Size:   12x  12x  12
 Iterations:   50
 Number of processes:     2

 Time step    1
 Time step   20
 Time step   40
 Time step   50

 Verification being performed for class S
 Accuracy setting for epsilon =  0.1000000000000E-07
 Comparison of RMS-norms of residual
           1   0.1619634321098E-01 0.1619634321098E-01 0.2998964438740E-14
           2   0.2197674516482E-02 0.2197674516482E-02 0.1359646828937E-12
           3   0.1517992765340E-02 0.1517992765340E-02 0.2359829414002E-12
           4   0.1502958443599E-02 0.1502958443599E-02 0.2178563602241E-13
           5   0.3426407315590E-01 0.3426407315590E-01 0.8708025940479E-14
 Comparison of RMS-norms of solution error
           1   0.6422331995796E-03 0.6422331995796E-03 0.1688175219212E-14
           2   0.8414434204735E-04 0.8414434204735E-04 0.5798262435090E-14
           3   0.5858826961649E-04 0.5858826961649E-04 0.1734885743100E-14
           4   0.5847422259516E-04 0.5847422259516E-04 0.1494911711129E-13
           5   0.1310334791411E-02 0.1310334791411E-02 0.7612298820307E-14
 Comparison of surface integral
               0.7841892886594E+01 0.7841892886594E+01 0.0000000000000E+00
 Verification Successful


 LU Benchmark Completed.
...
```

```bash
$ mpirun -mca plm_rsh_agent /opt/HPCmD/OpenMPI/HPCmD_plm_rsh_agent -n 2 -H node1,node2 bin/mg.S.2 


 NAS Parallel Benchmarks 3.3 -- MG Benchmark

 No input file. Using compiled defaults 
 Size:   32x  32x  32  (class S)
 Iterations:    4
 Number of processes:      2

 Initialization time:           0.011 seconds

  iter    1
  iter    4

 Benchmark completed 
 VERIFICATION SUCCESSFUL 
 L2 Norm is  0.5307707005735E-04
 Error is    0.1662242314632E-12
...
```

As we can see, all of them are successfully executed.

## A note on Docker Overlay Networks

Docker needs a _consul_ server for the overlay networks to work. This is probably because it does not use a DHCP or similar mechanism. It will probably use the _consul server_ to keep track of the IP leases, and it will probably get an unused IP lease in the overlay network, and set it will probably set it to the containers by issuing _ip_ or _ifconfig_ commands.

## Some previous work that I did

This section is included because it includes interesting material and one day may be useful.

### Approach 1

Let's have a HPCmD_dockerrun command like the next one (it will enable to shorten the docker run commandline to enable the home folder inside the container):

```bash
#!/bin/bash
DOCKER_OPTS="-v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /home/ubuntu:/home/ubuntu -u $(id -u):$(id -g) -w $(pwd)"
docker run $DOCKER_OPTS $@
```

Now I can issue a command like

```
$ mpirun -H node1,node2 bash -c "/home/ubuntu/HPCmD_dockerrun ubupy python /home/ubuntu/mpi_hello.py"
hello world from process  0
82fa5ff996b0
hello world from process  0
8294f854faa4
```

**What happened**: mpirun started the processes in the containers. The processes where containers which ran an MPI application. The container have no idea about the _external_ MPI environment, so they think that they are isolated MPI processes.

**What we need**: to enable the communication between nodes

#### Approach 2

I have found [this post](http://www.qnib.org/2016/03/31/dssh/) in which I saw that it is possible to use an external ssh application to spawn the processes from the Head Node Processor.

So I have created the _dockerssh_ wrapper to see what is happenind:

```bash
#!/bin/bash
set -x
ssh $@
```

And now I try the same command, but checking what is happening (the key argument is _plm_rsh_agent_):

```bash
mpirun -mca plm_rsh_agent fssh -H node1,node2 -n 2 bash -c "/home/ubuntu/HPCmD_dockerrun ubupy python /home/ubuntu/mpi_hello.py"
+ ssh node1 orted --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"4103995392"' -mca orte_ess_vpid 1 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"4103995392.0;tcp://10.153.72.131,172.17.0.1:59050"' --tree-spawn -mca plm_rsh_agent '"fssh"' -mca plm '"rsh"' --tree-spawn
+ ssh node2 orted --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"4103995392"' -mca orte_ess_vpid 2 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"4103995392.0;tcp://10.153.72.131,172.17.0.1:59050"' --tree-spawn -mca plm_rsh_agent '"fssh"' -mca plm '"rsh"' --tree-spawn
hello world from process  0
dd2d1d9c52fb
hello world from process  0
4a478821624d
```

**Additional problem**: I have realised that now I have other problem: the IP addresses inside the containers are not the same that outside the containers, and OpenMPI needs them. Digging a bit, it seems that OpenMPI launches the _orte_ daemon that is used to communicate the processes.

##### Notes

At one moment I'd need to control the IP addresses and ports that the containers will use. So I have been digging on this.

If we check the _orte_hnp_uri_ parameter, we can see that it is spawning the _orte daemon_ in an IP address, in one port. We can also check the environment variables and we will see that it exists a variable _OMPI_MCA_orte_local_daemon_uri_ for each daemon that is ran in the nodes. And it has the same features.

I have checked the help of open_mpi:

```bash
$ ompi_info --param oob tcp --level 9
```

And there I found the variables oob_tcp_static_ipv4_ports and oob_tcp_dynamic_ipv4_ports (among others), that enables me to control where the _orte daemon_ is listening.

If I run the next command:

```bash
$ mpirun -mca plm_rsh_agent fssh -mca oob_tcp_static_ipv4_ports 10000 -H node1,node2 -n 1 bash -c "env | grep orte_.*_uri"
+ ssh node1 orted --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"3195338752"' -mca orte_ess_vpid 1 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"3195338752.0;tcp://10.153.72.131,172.17.0.1:10000"' --tree-spawn -mca plm_rsh_agent '"fssh"' -mca oob_tcp_static_ipv4_ports '"10000"' -mca plm '"rsh"' --tree-spawn
+ ssh node2 orted --hnp-topo-sig 0N:1S:1L3:4L2:4L1:4C:8H:x86_64 -mca ess '"env"' -mca orte_ess_jobid '"3195338752"' -mca orte_ess_vpid 2 -mca orte_ess_num_procs '"3"' -mca orte_hnp_uri '"3195338752.0;tcp://10.153.72.131,172.17.0.1:10000"' --tree-spawn -mca plm_rsh_agent '"fssh"' -mca oob_tcp_static_ipv4_ports '"10000"' -mca plm '"rsh"' --tree-spawn
OMPI_MCA_orte_hnp_uri=3195338752.0;tcp://10.153.72.131,172.17.0.1:10000
OMPI_ARGV=-c env | grep orte_.*_uri
OMPI_MCA_orte_local_daemon_uri=3195338752.1;tcp://10.153.72.238,172.17.0.1:10000
```

I can see that the orte daemons are listening in the port that I have stated (i.e. 10000).

