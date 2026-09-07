#! /bin/bash
#
# Requires build dependencies for compiling Python via pyenv, e.g. on
# Oracle/RHEL-based systems:
#   sudo dnf install -y gcc make patch zlib-devel bzip2 bzip2-devel \
#       readline-devel sqlite sqlite-devel openssl-devel tk-devel \
#       libffi-devel xz-devel

set -euo pipefail

PYTHON_VERSION="3.12.3"

export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"

if [ ! -d "$PYENV_ROOT" ]; then
    echo "pyenv not found, installing to $PYENV_ROOT ..."
    git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
fi

export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

if ! pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
    echo "Building Python $PYTHON_VERSION with pyenv ..."
    pyenv install "$PYTHON_VERSION"
fi

pyenv shell "$PYTHON_VERSION"

python -m venv CLAUDE_IP
