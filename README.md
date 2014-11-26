cluster-controller
==================

Shell script to run a project on PBS based clusters

Connection to cluster via ssh, keyfiles usable

**Installation**

Extract or clone files to `<your project directory>/clustering`.

(optional) Make `cluster-controller.sh` executable with `chmod u+x cluster-controller.sh`.

Modify the settings in the `cluster-controller.conf`.

**Basic usage**

Just run `sh cluster-controller.sh` or `./cluster-controller.sh` (if exectuable). You will get a help displaying all subcommands available.

For now theses subcommands are:

 * `sync`
 * `start`
 * `status`
 * `stop`
 * `results`
 * `ssh`

All subcommands have their own help and options to run.