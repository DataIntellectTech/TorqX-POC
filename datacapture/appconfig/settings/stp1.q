/ stp1: one log per table per hour, logging and publishing a memory batch on each -t tick (QCMD in setenv.sh)
schemafile:"database.q"
stplgbatchmode:`memorybatch
stplgmultilog:`tabperiod
stplgmultilogperiod:0D01
