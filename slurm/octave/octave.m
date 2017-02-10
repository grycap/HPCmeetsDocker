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
m = 10000;
n = 1000;
args = argv();
if (nargin>0) m=str2num(args{1}); endif
if (nargin>1) m=str2num(args{2}); endif
A = rand(m, n);
tic(); A*A'; toc()
tic(); B=A'*A; toc()
tic(); B*inv(B); toc()
