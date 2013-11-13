#!/usr/bin/env bash
bin=`readlink "$0"`
if [ "$bin" == "" ]; then
 bin=$0
fi
bin=`dirname "$bin"`
bin=`cd "$bin"; pwd`

. "$bin"/chorus-config.sh

ALPINE_PID_FILE="$ALPINE_HOME"/alpine.pid

if [ -f $ALPINE_PID_FILE ]; then
  if kill -0 `cat $ALPINE_PID_FILE` > /dev/null 2>&1; then
    log "stopping alpine "
    CATALINA_PID=$ALPINE_PID_FILE $ALPINE_HOME/alpine_control.sh stop >/dev/null
    wait_for_stop $ALPINE_PID_FILE
    rm -f $ALPINE_PID_FILE
  else
    log "could not stop alpine. check that process `cat $ALPINE_PID_FILE` exists"
  fi
else
  log "no alpine to stop"
fi