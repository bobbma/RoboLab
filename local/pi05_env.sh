#!/usr/bin/env bash

ROBO_DATA_ROOT="/mnt/38_store/myx/robolab"
export XDG_CACHE_HOME="$ROBO_DATA_ROOT/cache/xdg"
export UV_CACHE_DIR="$ROBO_DATA_ROOT/cache/uv"
export OPENPI_DATA_HOME="$ROBO_DATA_ROOT/openpi-data"
export HF_HOME="$ROBO_DATA_ROOT/cache/huggingface"
export TMPDIR="$ROBO_DATA_ROOT/tmp"
export OMNI_KIT_ACCEPT_EULA=Y
