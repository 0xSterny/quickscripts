#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   addtool <git-url> [dir-name] [--shell bash|zsh]
# Examples:
#   addtool https://github.com/ThePorgs/impacket
#   addtool https://github.com/0xSterny/LastResorNTDS lastresorntds --shell zsh
#   addtool https://github.com/my/tool --tools-dir '~/my-tools'

TOOLS_ROOT="${HOME}/tools"

# -------------------------------
# Parse args
# -------------------------------
SHELL_RC=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --shell)
            shift
            SHELL_RC="$1"
            ;;
        --tools-dir)
            shift
            TOOLS_ROOT="$1"
            ;;
        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift || true
done

# Expand tilde in TOOLS_ROOT
TOOLS_ROOT="${TOOLS_ROOT/#\~/$HOME}"

set +u
GIT_URL="${POSITIONAL[0]}"
DIR_NAME="${POSITIONAL[1]}"
set -u

if [[ -z "$GIT_URL" ]]; then
    echo "Usage: addtool <git-url> [dir-name] [--shell bash|zsh]"
    exit 1
fi

# Infer directory name if not provided
if [[ -z "${DIR_NAME:-}" ]]; then
  DIR_NAME="$(basename -s .git "$GIT_URL")"
fi

# Auto-detect shell RC file if --shell not given
if [[ -z "$SHELL_RC" ]]; then
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        SHELL_RC="zsh"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        SHELL_RC="bash"
    else
        # fallback to bash if unknown shell
        SHELL_RC="bash"
    fi
fi

if [[ "$SHELL_RC" == "bash" ]]; then
    RC_FILE="$HOME/.bashrc"
elif [[ "$SHELL_RC" == "zsh" ]]; then
    RC_FILE="$HOME/.zshrc"
else
    echo "Invalid --shell option. Use bash or zsh"
    exit 1
fi

TARGET_DIR="${TOOLS_ROOT}/${DIR_NAME}"
VENV_DIR="${TARGET_DIR}/venv"

echo "→ Installing into $TARGET_DIR (shell RC: $RC_FILE)"

# -------------------------------
# Clone repo
# -------------------------------
mkdir -p "$TOOLS_ROOT"
if [[ -d "$TARGET_DIR/.git" ]]; then
    echo "→ Updating existing repo..."
    git -C "$TARGET_DIR" pull --rebase || true
else
    echo "→ Cloning $GIT_URL"
    git clone --depth 1 "$GIT_URL" "$TARGET_DIR"
fi

# -------------------------------
# Create venv
# -------------------------------
if [[ ! -d "$VENV_DIR" ]]; then
    echo "→ Creating venv"
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel >/dev/null

if [[ -f "$TARGET_DIR/requirements.txt" ]]; then
    echo "→ Installing requirements.txt"
    "$VENV_DIR/bin/pip" install -r "$TARGET_DIR/requirements.txt"
elif [[ -f "$TARGET_DIR/pyproject.toml" || -f "$TARGET_DIR/setup.py" ]]; then
    echo "→ Installing python package"
    (cd "$TARGET_DIR" && "$VENV_DIR/bin/pip" install .)
else
    echo "→ No requirements.txt or setup.py found — skipping pip install."
fi

# -------------------------------
# Ensure auto-PATH snippet
# -------------------------------
AUTOPATH_SNIPPET="# Auto-add all venv/bin dirs under ${TOOLS_ROOT} (managed by addtool)"
if ! grep -Fq "managed by addtool" "$RC_FILE" 2>/dev/null; then
    echo "→ Adding PATH loader to $RC_FILE"
    {
      echo ""
      echo "$AUTOPATH_SNIPPET"
      echo "for d in \"${TOOLS_ROOT}\"/*/venv/bin; do"
      echo '  [ -d "$d" ] && PATH="$d:$PATH"'
      echo "done"
      echo "export PATH"
      echo ""
      echo "alias refresh-tools='source ${RC_FILE}'"
    } >> "$RC_FILE"
else
    if ! grep -Fq "$AUTOPATH_SNIPPET" "$RC_FILE" 2>/dev/null; then
        echo "✓ PATH loader for a different directory already exists in $RC_FILE"
        echo "  Please update your RC file manually if you want to switch to ${TOOLS_ROOT}"
    else
        echo "✓ PATH loader already exists in $RC_FILE"
    fi
fi

echo "→ To load new tool now, run:"
echo "   source $RC_FILE"
echo ""
echo "✅ Done — venv created at:"
echo "   $VENV_DIR"
echo ""
echo "Try running a tool from:"
echo "   $VENV_DIR/bin"
