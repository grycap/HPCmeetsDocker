# Pruebas con Infiniband

En principio, parece que si tuvieramos _IBoIP_ podríamos utilizar IB de forma estándar, porque estaría IP-enabled. Pero en principio IB no es una red con IP y saca más prestaciones utilizando las funciones nativas de IB.

Al utilizar IB, utiliza funciones específicas de IB que le dan las prestaciones y no se utiliza el stack TCP. Por tanto, además libera el kernel. Al utilizar IBoIP, se utilizan algunas funciones de IB, enmascaradas a través de un dispositivo con características IP. Pero entonces pasa por el stack TCP y no saca las prestaciones de IB.

Hay una distibución específica de mpich para altas prestaciones (entre otras, Infiniband): [MVAMPICH](http://mvapich.cse.ohio-state.edu).

Para aprender un poco más acerca de IB, tenemos la [siguiente pagina](https://pkg-ofed.alioth.debian.org/howto/infiniband-howto.html). Entre otros, utiliza comandos como ```ibstat``` o ```ibping```. También explica cómo probarla con OpenMPI y, con respecto a esto, dice la siguiente frase, que es bastante importante:
    
    OpenMPI uses IPoIB for job startup and tear-down.

Eso significa que necesita tener _IPoIB_ para, de alguna forma, identificar los nodos y después ya utilizaría las tarjetas de IB. Esto induce a pensar que si sólo usamos _IPoIB_ no sacaremos todas las prestaciones de IB.

## Docker e IB
He revisado un poco por ahí y me he encontrado los siguientes recursos:

Alguien que intenta hacer [IB bypassing a contendores Docker](https://serverfault.com/questions/638710/passing-through-rdma-network-devices-to-docker-containers). Básicamente sigue la aproximación de mapear el interfaz y ponerle el interfaz que tiene IPoIB.

Buscando un poco más, he visto que hay un tipo que ha hecho un contenedor para [tener acceso a IB en Docker](https://github.com/ambu50/wrapper-sq/tree/master/docker). En realidad es básicamente lo mismo que hace el otro, pero tiene un aspecto importante que es el uso de ```--net=host```.

Esto puede ser importante en nuestro punto de trabajo ya que en realidad un usuario que no lanza aplicaciones containerizadas tendría acceso a todo el stack de red del nodo y, por tanto, no sería descabellado hacer esto. En este sentido, potencialmente **nos evitaríamos el rollo de las redes overlay** y los **trapicheos de red** ya que los demonios MPI se apañarían metiéndose en el puerto que pudieran, pero estarían **dentro** del contenedor y por tanto asociados a la aplicación.

    TODO: Hay que probar esto!!!

El resumen es que, al parecer, lo que habría que hacer es lanzar el contenedor docker, con el dispositivo ```/dev/infiniband``` accesible desde el contenedor y tendríamos que tener el dispositivo con posibilidad de _IPoIB_ también accesible desde el contenedor y dentro los drivers de userspace para infiniband.

En [este enlace](http://qiita.com/syoyo/items/bea48de8d7c6d8c73435) hay un chino que explica como hacerlo más o menos. El problema es que está en chino, pero los comandos son legibles y *mas o menos* se puede seguir.

Finalmente hay unos tipos que han hecho algo de prueba de prestaciones de contenedores Docker con IB vs máquinas virtuales con IB. Tienen [este artículo](http://ieeexplore.ieee.org/document/7809565/).

# Pruebas

He creado el siguiente Dockerfile para pruebas:

```dockerfile
FROM ubuntu
RUN apt-get update && apt-get install -y iproute2 infiniband-diags ibutils libmlx5-1 ibverbs-utils perftest strace
RUN apt-get install -y openmpi-bin
RUN apt-get install -y build-essential wget libopenmpi-dev
RUN cd /opt && wget https://software.intel.com/sites/default/files/managed/76/6c/IMB_2017_Update2.tgz && tar xfz IMB_2017_Update2.tgz && cd imb/imb/src && sed -i 's/mpiicc/mpicc/' make_ict && make -f make_ict && cp $(find . -executable -type f) /usr/bin
RUN apt-get install -y netcat
RUN apt-get install -y ssh
```

Lo construyo con

```bash
docker build . -t hpcmd
```

He creado el siguiente script:

```bash
#!/bin/bash

DOCKER_PASS="-v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro"
DOCKER_FOLDERS="-v /home:/home"
DOCKER_WD="-w $(pwd)"
DOCKER_OPTS=
DOCKER_IB="-v /dev/infiniband:/dev/infiniband"
DOCKER_IB="--device=/dev/infiniband:/dev/infiniband"

END=False
PARAMS=( )
GET_HOME=False
C_USER=$(whoami)

while [ $# -gt 0 -a "$END" == "False" ]; do
case $1 in
-u) shift
    C_USER=$1
    id -u $1 2> /dev/null > /dev/null || { echo "invalid user $1"; exit 1; }
    DOCKER_OPTS="$DOCKER_OPTS -u $(id -u $1):$(id -g $1)";;
-h) GET_HOME=True;;
--) END=True
    PARAMS=()
     ;;
*) PARAMS+=($1);;
esac
shift
done

if [ "$GET_HOME" == "True" ]; then
   DOCKER_WD="-w $(eval echo ~$C_USER)"
fi

DOCKER_OPTS="$DOCKER_OPTS $DOCKER_IB"

set -x
if [ "$END" == "False" ]; then
docker run $DOCKER_PASS $DOCKER_FOLDERS $DOCKER_WD $DOCKER_OPTS -it ${PARAMS[@]}
else
docker run $DOCKER_PASS $DOCKER_FOLDERS $DOCKER_WD $DOCKER_OPTS -it $@
fi
```

y arranco contenedores de la siguiente forma:

```bash
./rundocker -h -u sie -- --net=host hpcmd bash
```

y ahi ya puedo "supuestamente" utilizar la infiniband. Digo supuestamente porque parece que los nodos internos no tienen el usuario "sie" ni el "home" montado y por lo tanto, no puedo hacer pruebas.

En estos momentos estoy lanzando pruebas que supuestamente utilizan IB (saca mensajes relativos a IB) pero al no tener el home compartido no puedo probar.

```bash
mpirun --mca btl_openib_verbose 1 --mca btl ^tcp -n 2 mpitests-IMB-MPI1 PingPong
```

```bash
tests
```