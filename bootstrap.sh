#!/usr/bin/env bash
# Duke & Duke -- bootstrap.sh
#
# Single entry point on a fresh machine.
# Run from your home directory AFTER creating secrets.conf:
#
#   cd ~
#   nano secrets.conf          # fill in all values
#   chmod +x bootstrap.sh
#   bash bootstrap.sh
#
# What this does:
#   1. Validates secrets.conf exists and has required fields
#   2. Installs git if missing
#   3. Clones the duke-and-duke repo to /opt/duke-and-duke/app
#   4. Makes deploy scripts executable
#   5. Hands off to deploy.sh prereqs
#
# The repo must NOT be cloned to your home directory.
# It lives at /opt/duke-and-duke/app so the dukeduke service account
# can access it without home directory permission issues.

set -eo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; exit 1; }

if [ "$EUID" -eq 0 ]; then
    error "Do not run as root. Run as your regular user."
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Duke & Duke  v2.0  --  Bootstrap                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Locate secrets.conf ───────────────────────────────────────────────────────
SECRETS_FILE="$HOME/secrets.conf"

if [ ! -f "$SECRETS_FILE" ]; then
    error "secrets.conf not found at $HOME/secrets.conf

  Create it first:
    cp /path/to/secrets.conf ~/secrets.conf
    nano ~/secrets.conf"
fi

info "secrets.conf found: $SECRETS_FILE"
chmod 600 "$SECRETS_FILE"

# Source secrets
set -a
# shellcheck disable=SC1090
source "$SECRETS_FILE" || true
set +a

# ── Validate required fields ──────────────────────────────────────────────────
check_secret() {
    local key="$1"
    local val
    val=$(grep "^${key}=" "$SECRETS_FILE" | cut -d= -f2- | tr -d '[:space:]"')
    if [ -z "$val" ]; then
        error "secrets.conf: $key is empty. Fill in all required values first."
    fi
}

check_secret "ANTHROPIC_API_KEY"
check_secret "SMTP_USER"
check_secret "SMTP_PASS"
check_secret "REPORT_EMAIL"
check_secret "GITHUB_TOKEN"
check_secret "GITHUB_REPO"
success "secrets.conf validated"

# ── Install git ───────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    info "Installing git..."
    sudo apt-get update -y -q
    sudo apt-get install -y -q git
    success "git installed: $(git --version)"
else
    success "git already installed: $(git --version)"
fi

# ── Clone repo to /opt/duke-and-duke/app ─────────────────────────────────────
REPO_DIR="/opt/duke-and-duke/app"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/wmfreeman/duke-and-duke.git}"
GITHUB_USER="${GITHUB_USER:-wmfreeman}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Embed token in URL for private repo clone
CLONE_URL="${GITHUB_REPO/https:\/\//https://${GITHUB_USER}:${GITHUB_TOKEN}@}"

sudo mkdir -p /opt/duke-and-duke
sudo chown "$USER:$USER" /opt/duke-and-duke

if [ -d "$REPO_DIR/.git" ]; then
    info "Repo already cloned at $REPO_DIR — pulling latest..."
    cd "$REPO_DIR"
    git remote set-url origin "$CLONE_URL"
    git pull --ff-only
    success "Repo updated"
else
    info "Cloning repo to $REPO_DIR ..."
    git clone "$CLONE_URL" "$REPO_DIR"
    success "Repo cloned: $REPO_DIR"
fi

# Store credentials for future git pulls
git -C "$REPO_DIR" config credential.helper store
git -C "$REPO_DIR" remote set-url origin "$CLONE_URL"

# ── Make scripts executable ───────────────────────────────────────────────────
chmod +x "$REPO_DIR/deploy.sh"
chmod +x "$REPO_DIR/setup/"*.sh 2>/dev/null || true
success "Deploy scripts made executable"

# ── Hand off to deploy.sh prereqs ────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}Bootstrap complete.${NC}"
echo -e "Repo is at: ${CYAN}$REPO_DIR${NC}"
echo ""
echo -e "Starting prereqs now..."
echo ""

cd "$REPO_DIR"
exec bash deploy.sh prereqs
