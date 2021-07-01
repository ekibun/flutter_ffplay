#!/bin/bash
set -e

if [ $1 == "ln" ]; then
  tgtdir=$( dirname "$3" )
  tgtbase=$( basename "$3" )
  windir=$( wslpath -w "$tgtdir" )
  cmd.exe /c mklink /J "$windir\\$tgtbase" "$( wslpath -w "$2" )"
else
  # https://github.com/microsoft/WSL/issues/6420
  echo "--wsl.wrap---$1"

  tmp=$( mktemp -p /tmp )
  mv $tmp $tmp.bat
  trap "rm $tmp.bat; exit" SIGHUP SIGINT SIGTERM
  echo $1 ${*:2} > $tmp.bat
  cmd.exe /C $( wslpath -m $tmp.bat )
  rm $tmp.bat
fi