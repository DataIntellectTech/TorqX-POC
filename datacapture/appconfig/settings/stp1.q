/ one log per table per hour; memory batch published on the -t timer (setenv.sh)
schemafile:"database.q"
stplgbatchmode:`memorybatch
stplgmultilog:`tabperiod
stplgmultilogperiod:0D01
