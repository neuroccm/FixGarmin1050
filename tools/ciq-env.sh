#!/usr/bin/env bash
# Source this file: environment for Connect IQ builds on this Mac.
#   source tools/ciq-env.sh
_ciq_cfg="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
export CIQ_SDK="$(tr -d '\n' < "$_ciq_cfg")"
export CIQ_SDK="${CIQ_SDK%/}"
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$CIQ_SDK/bin:$PATH"
export CIQ_KEY="$HOME/.garmin-dev/developer_key.der"
unset _ciq_cfg
