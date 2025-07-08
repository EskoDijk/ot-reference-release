#!/bin/bash
# Script to activate the Python virtual env and bootstrap.

set -euox pipefail

activate_python_venv()
{
    if [[ ! -d .venv ]]; then
        python3 -m venv .venv
    fi
    # shellcheck source=/dev/null
    source .venv/bin/activate
}

activate_python_venv

./script/bootstrap.bash
