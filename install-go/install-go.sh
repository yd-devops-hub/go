#!/usr/bin/env bash
#
# install-go.sh - Install the Go toolchain on Linux from the official go.dev tarball.
#
# Defaults to a per-user install in ~/.local/go with no sudo required.
# See --help for the full option list.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly SCRIPT_NAME="install-go.sh"
readonly MARKER_BEGIN="# >>> install-go.sh >>>"
readonly MARKER_END="# <<< install-go.sh <<<"
# dl.google.com serves the raw tarball and .sha256 directly (no HTML redirect
# page), so we use it as the canonical download host. go.dev/dl is a front end
# that HTTP-redirects for the tarball but returns HTML for .sha256.
readonly GO_DL_BASE="https://dl.google.com/go"
readonly GO_VERSION_URL="https://go.dev/VERSION?m=text"

# ---------------------------------------------------------------------------
# Defaults (overridable via flags)
# ---------------------------------------------------------------------------

VERSION="latest"
SCOPE="user"          # user | system | prefix
PREFIX=""             # explicit install root when SCOPE=prefix
GOPATH_DIR="${HOME}/go"
FORCE=0
UNINSTALL=0
WRITE_SHELL_CONFIG=1
DRY_RUN=0

# Resolved at runtime
INSTALL_ROOT=""       # parent dir that will contain the "go" folder
INSTALL_DIR=""        # $INSTALL_ROOT/go
GO_ARCH=""
DISTRO_ID=""
DISTRO_LIKE=""
IS_MUSL=0
DOWNLOADER=""
TMPDIR_PATH=""
MODIFIED_FILES=()

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

_has_tty() { [[ -t 2 ]]; }

if _has_tty; then
    readonly C_RESET=$'\033[0m'
    readonly C_BOLD=$'\033[1m'
    readonly C_RED=$'\033[31m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_GREEN=$'\033[32m'
    readonly C_BLUE=$'\033[34m'
else
    readonly C_RESET="" C_BOLD="" C_RED="" C_YELLOW="" C_GREEN="" C_BLUE=""
fi

log_info()  { printf '%s[info]%s  %s\n'  "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_warn()  { printf '%s[warn]%s  %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
log_ok()    { printf '%s[ok]%s    %s\n'  "$C_GREEN"  "$C_RESET" "$*" >&2; }

die() {
    log_error "$*"
    exit 1
}

# Run a command, or just print it under --dry-run.
run() {
    if (( DRY_RUN )); then
        printf '%s[dry-run]%s %s\n' "$C_BOLD" "$C_RESET" "$*" >&2
    else
        eval "$@"
    fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
${SCRIPT_NAME} - install Go on Linux from the official go.dev tarball

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -v, --version <X.Y.Z|latest>   Go version to install (default: latest)
        --system                   Install to /usr/local/go (requires sudo)
        --user                     Install to ~/.local/go (default)
        --prefix <dir>             Custom install root; Go goes in <dir>/go
        --gopath <dir>             GOPATH to configure (default: ~/go)
        --force                    Reinstall even if the target version is present
        --uninstall                Remove Go and env lines added by this script
        --no-shell-config          Do not modify any shell rc files
        --dry-run                  Print what would be done, do not change anything
    -h, --help                     Show this help

EXAMPLES:
    ${SCRIPT_NAME}                         # latest Go, per-user install
    ${SCRIPT_NAME} --version 1.22.5        # pinned version
    ${SCRIPT_NAME} --system                # system-wide install in /usr/local/go
    ${SCRIPT_NAME} --prefix /opt           # installs to /opt/go
    ${SCRIPT_NAME} --uninstall             # remove what this script installed

After install, open a new shell (or source your rc file) so PATH changes take effect.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -v|--version)
                [[ $# -ge 2 ]] || die "--version requires an argument"
                VERSION="$2"; shift 2 ;;
            --version=*)
                VERSION="${1#*=}"; shift ;;
            --system)
                SCOPE="system"; shift ;;
            --user)
                SCOPE="user"; shift ;;
            --prefix)
                [[ $# -ge 2 ]] || die "--prefix requires an argument"
                SCOPE="prefix"; PREFIX="$2"; shift 2 ;;
            --prefix=*)
                SCOPE="prefix"; PREFIX="${1#*=}"; shift ;;
            --gopath)
                [[ $# -ge 2 ]] || die "--gopath requires an argument"
                GOPATH_DIR="$2"; shift 2 ;;
            --gopath=*)
                GOPATH_DIR="${1#*=}"; shift ;;
            --force)
                FORCE=1; shift ;;
            --uninstall)
                UNINSTALL=1; shift ;;
            --no-shell-config)
                WRITE_SHELL_CONFIG=0; shift ;;
            --dry-run)
                DRY_RUN=1; shift ;;
            -h|--help)
                usage; exit 0 ;;
            --)
                shift; break ;;
            -*)
                die "unknown option: $1 (use --help)" ;;
            *)
                die "unexpected positional argument: $1" ;;
        esac
    done

    case "$SCOPE" in
        user)   INSTALL_ROOT="${HOME}/.local"; INSTALL_DIR="${INSTALL_ROOT}/go" ;;
        system) INSTALL_ROOT="/usr/local";     INSTALL_DIR="${INSTALL_ROOT}/go" ;;
        prefix)
            [[ -n "$PREFIX" ]] || die "--prefix requires a directory"
            # Normalize: remove trailing slash.
            PREFIX="${PREFIX%/}"
            INSTALL_ROOT="$PREFIX"
            INSTALL_DIR="${INSTALL_ROOT}/go"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Platform / distro detection
# ---------------------------------------------------------------------------

detect_platform() {
    local kernel arch
    kernel="$(uname -s)"
    [[ "$kernel" == "Linux" ]] || die "this script supports Linux only (got: $kernel)"

    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)       GO_ARCH="amd64" ;;
        aarch64|arm64)      GO_ARCH="arm64" ;;
        armv6l)             GO_ARCH="armv6l" ;;
        armv7l|armv7*)      GO_ARCH="armv6l"
                            log_warn "detected $arch; Go only ships armv6l binaries, using armv6l" ;;
        i686|i386)          GO_ARCH="386" ;;
        riscv64)            GO_ARCH="riscv64" ;;
        loongarch64)        GO_ARCH="loong64" ;;
        ppc64le)            GO_ARCH="ppc64le" ;;
        s390x)              GO_ARCH="s390x" ;;
        *) die "unsupported CPU architecture: $arch" ;;
    esac
}

detect_distro() {
    if [[ -r /etc/os-release ]]; then
        # Sourced in a subshell so that keys like VERSION, NAME, etc. don't
        # clobber this script's own variables (e.g. VERSION).
        DISTRO_ID="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
        DISTRO_LIKE="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi

    # musl detection: Alpine's ldd prints to stderr but exits non-zero.
    # Also covers Void musl, postmarketOS, etc.
    if command -v ldd >/dev/null 2>&1; then
        if ldd --version 2>&1 | grep -qi musl; then
            IS_MUSL=1
        fi
    fi
    if [[ "$DISTRO_ID" == "alpine" ]]; then
        IS_MUSL=1
    fi

    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        die "neither curl nor wget is installed; please install one and retry"
    fi

    if (( IS_MUSL )); then
        if (( FORCE )); then
            log_warn "musl libc detected (e.g. Alpine). Official Go binaries are built against glibc."
            log_warn "Continuing because --force was supplied; if Go fails to run, use your package manager (e.g. 'apk add go')."
        else
            log_error "musl libc detected (e.g. Alpine). Official Go binaries are built against glibc and will not run."
            log_error "Use your package manager instead (e.g. 'sudo apk add go'), or re-run with --force to override."
            exit 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# Downloading
# ---------------------------------------------------------------------------

fetch() {
    # fetch <url> <dest>  (dest "-" means stdout)
    local url="$1" dest="$2"
    case "$DOWNLOADER" in
        curl)
            if [[ "$dest" == "-" ]]; then
                curl -fsSL "$url"
            else
                curl -fsSL -o "$dest" "$url"
            fi
            ;;
        wget)
            if [[ "$dest" == "-" ]]; then
                wget -qO- "$url"
            else
                wget -qO "$dest" "$url"
            fi
            ;;
    esac
}

resolve_version() {
    if [[ "$VERSION" == "latest" ]]; then
        log_info "resolving latest Go version from go.dev"
        local line
        if ! line="$(fetch "$GO_VERSION_URL" - 2>/dev/null | head -n1 | tr -d '\r\n ')"; then
            die "failed to fetch latest version from $GO_VERSION_URL (check network)"
        fi
        [[ -n "$line" ]] || die "empty response from $GO_VERSION_URL"
        # Response looks like: go1.24.2
        VERSION="${line#go}"
    fi

    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([a-z0-9]+)?$ ]]; then
        die "invalid version: '$VERSION' (expected e.g. 1.22.5, 1.22, or 1.23rc1)"
    fi
    log_info "target Go version: $VERSION"
}

# ---------------------------------------------------------------------------
# Existing install check
# ---------------------------------------------------------------------------

check_existing() {
    if [[ ! -x "${INSTALL_DIR}/bin/go" ]]; then
        return 0
    fi
    local current
    current="$("${INSTALL_DIR}/bin/go" version 2>/dev/null | awk '{print $3}' | sed 's/^go//')" || true
    if [[ -n "$current" ]]; then
        log_info "found existing Go ${current} at ${INSTALL_DIR}"
        if [[ "$current" == "$VERSION" ]]; then
            if (( FORCE )); then
                log_warn "same version already installed; reinstalling because --force was given"
            else
                log_ok "Go ${VERSION} is already installed at ${INSTALL_DIR}; nothing to do (use --force to reinstall)"
                # Still ensure shell config is in place.
                if (( WRITE_SHELL_CONFIG )); then
                    configure_shells
                    print_summary
                fi
                exit 0
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Download + verify + install
# ---------------------------------------------------------------------------

download_and_verify() {
    local tar_name="go${VERSION}.linux-${GO_ARCH}.tar.gz"
    local tar_url="${GO_DL_BASE}/${tar_name}"
    local sha_url="${tar_url}.sha256"
    local tar_path="${TMPDIR_PATH}/${tar_name}"
    local sha_path="${tar_path}.sha256"

    if (( DRY_RUN )); then
        printf '%s[dry-run]%s would download %s\n' "$C_BOLD" "$C_RESET" "$tar_url" >&2
        printf '%s[dry-run]%s would download %s\n' "$C_BOLD" "$C_RESET" "$sha_url" >&2
        printf '%s[dry-run]%s would verify sha256\n' "$C_BOLD" "$C_RESET" >&2
        TAR_PATH="$tar_path"
        return 0
    fi

    log_info "downloading ${tar_url}"
    if ! fetch "$tar_url" "$tar_path"; then
        die "download failed for ${tar_url} (version or arch may not exist)"
    fi

    log_info "downloading checksum"
    if ! fetch "$sha_url" "$sha_path"; then
        die "checksum download failed for ${sha_url}"
    fi

    log_info "verifying sha256"
    local expected actual
    expected="$(tr -d '[:space:]' <"$sha_path")"
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        die "unexpected checksum content (not a 64-hex-char sha256); got: ${expected:0:80}..."
    fi
    actual="$(sha256sum "$tar_path" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
        die "sha256 mismatch!  expected=${expected}  actual=${actual}"
    fi
    log_ok "checksum verified"

    TAR_PATH="$tar_path"
}

install_tarball() {
    local use_sudo=""
    if [[ "$SCOPE" == "system" ]]; then
        if [[ $EUID -ne 0 ]]; then
            command -v sudo >/dev/null 2>&1 || die "--system install requires root or sudo"
            use_sudo="sudo"
        fi
    elif [[ "$SCOPE" == "prefix" ]]; then
        # Use sudo only if we lack write permission to INSTALL_ROOT (or its parent).
        local probe="$INSTALL_ROOT"
        [[ -d "$probe" ]] || probe="$(dirname "$probe")"
        if [[ ! -w "$probe" && $EUID -ne 0 ]]; then
            command -v sudo >/dev/null 2>&1 || die "no write permission to $INSTALL_ROOT and sudo not available"
            use_sudo="sudo"
        fi
    fi

    log_info "installing to ${INSTALL_DIR}"
    run "${use_sudo} mkdir -p $(printf '%q' "$INSTALL_ROOT")"
    if [[ -d "$INSTALL_DIR" ]]; then
        log_info "removing previous ${INSTALL_DIR}"
        run "${use_sudo} rm -rf $(printf '%q' "$INSTALL_DIR")"
    fi
    run "${use_sudo} tar -C $(printf '%q' "$INSTALL_ROOT") -xzf $(printf '%q' "$TAR_PATH")"
    log_ok "extracted Go ${VERSION} to ${INSTALL_DIR}"
}

# ---------------------------------------------------------------------------
# Shell configuration
# ---------------------------------------------------------------------------

posix_env_block() {
    cat <<EOF
${MARKER_BEGIN}
# Added by ${SCRIPT_NAME} on $(date -u +%Y-%m-%dT%H:%M:%SZ)
export GOROOT="${INSTALL_DIR}"
export GOPATH="${GOPATH_DIR}"
export GOBIN="\$GOPATH/bin"
case ":\$PATH:" in
    *":\$GOROOT/bin:"*) ;;
    *) export PATH="\$GOROOT/bin:\$PATH" ;;
esac
case ":\$PATH:" in
    *":\$GOBIN:"*) ;;
    *) export PATH="\$GOBIN:\$PATH" ;;
esac
${MARKER_END}
EOF
}

fish_env_block() {
    cat <<EOF
${MARKER_BEGIN}
# Added by ${SCRIPT_NAME} on $(date -u +%Y-%m-%dT%H:%M:%SZ)
set -gx GOROOT "${INSTALL_DIR}"
set -gx GOPATH "${GOPATH_DIR}"
set -gx GOBIN "\$GOPATH/bin"
if not contains "\$GOROOT/bin" \$PATH
    set -gx PATH "\$GOROOT/bin" \$PATH
end
if not contains "\$GOBIN" \$PATH
    set -gx PATH "\$GOBIN" \$PATH
end
${MARKER_END}
EOF
}

# Remove any existing MARKER_BEGIN..MARKER_END block from a file (in place).
strip_marker_block() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if ! grep -qF "$MARKER_BEGIN" "$file"; then
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    # Use awk to strip inclusive range.
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
        BEGIN { skip = 0 }
        {
            if (!skip && index($0, b)) { skip = 1; next }
            if (skip  && index($0, e)) { skip = 0; next }
            if (!skip) print
        }
    ' "$file" > "$tmp"
    if (( DRY_RUN )); then
        printf '%s[dry-run]%s would rewrite %s (strip marker block)\n' "$C_BOLD" "$C_RESET" "$file" >&2
        rm -f "$tmp"
    else
        # Preserve trailing newline hygiene.
        mv "$tmp" "$file"
    fi
}

write_block_to_file() {
    # write_block_to_file <file> <block-producer-fn>
    local file="$1" producer="$2"
    local dir
    dir="$(dirname "$file")"
    if (( DRY_RUN )); then
        printf '%s[dry-run]%s would update %s\n' "$C_BOLD" "$C_RESET" "$file" >&2
        MODIFIED_FILES+=("$file")
        return 0
    fi
    mkdir -p "$dir"
    # Strip old block if present, then append fresh one.
    strip_marker_block "$file"
    # Ensure file ends with newline before appending.
    if [[ -s "$file" ]] && [[ "$(tail -c1 "$file" | od -An -c | tr -d ' ')" != "\\n" ]]; then
        printf '\n' >> "$file"
    fi
    "$producer" >> "$file"
    MODIFIED_FILES+=("$file")
}

configure_shells() {
    if (( ! WRITE_SHELL_CONFIG )); then
        log_info "skipping shell config (--no-shell-config)"
        return 0
    fi

    if [[ "$SCOPE" == "system" && $EUID -eq 0 ]]; then
        local sysfile="/etc/profile.d/go.sh"
        log_info "writing system-wide profile: $sysfile"
        if (( DRY_RUN )); then
            printf '%s[dry-run]%s would write %s\n' "$C_BOLD" "$C_RESET" "$sysfile" >&2
            MODIFIED_FILES+=("$sysfile")
        else
            posix_env_block > "$sysfile"
            chmod 0644 "$sysfile"
            MODIFIED_FILES+=("$sysfile")
        fi
    fi

    # Per-user shell config is still useful even for --system, because the
    # user's interactive shell sets PATH via rc files.
    local target
    # bash
    target="${HOME}/.bashrc"
    log_info "updating $target (bash)"
    write_block_to_file "$target" posix_env_block

    # If .bash_profile or .profile exists, ensure it sources .bashrc-equivalent env.
    # We do NOT rewrite them; most distros already source .bashrc. But if neither
    # .bash_profile nor .profile exists, create ~/.profile with the block so
    # login shells (e.g. ssh non-interactive) pick it up.
    if [[ ! -f "${HOME}/.bash_profile" && ! -f "${HOME}/.profile" ]]; then
        target="${HOME}/.profile"
        log_info "creating $target (login shells)"
        write_block_to_file "$target" posix_env_block
    fi

    # zsh (only if zsh is installed or .zshrc already exists)
    if command -v zsh >/dev/null 2>&1 || [[ -f "${HOME}/.zshrc" ]]; then
        target="${HOME}/.zshrc"
        log_info "updating $target (zsh)"
        write_block_to_file "$target" posix_env_block
    fi

    # fish (only if fish is installed or its config dir already exists)
    if command -v fish >/dev/null 2>&1 || [[ -d "${HOME}/.config/fish" ]]; then
        target="${HOME}/.config/fish/conf.d/go.fish"
        log_info "writing $target (fish)"
        if (( DRY_RUN )); then
            printf '%s[dry-run]%s would write %s\n' "$C_BOLD" "$C_RESET" "$target" >&2
            MODIFIED_FILES+=("$target")
        else
            mkdir -p "$(dirname "$target")"
            fish_env_block > "$target"
            MODIFIED_FILES+=("$target")
        fi
    fi

    # Ensure GOPATH/bin directory exists so PATH entries aren't dead.
    run "mkdir -p $(printf '%q' "${GOPATH_DIR}/bin")"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    log_info "uninstalling Go from ${INSTALL_DIR}"

    local use_sudo=""
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ ! -w "$(dirname "$INSTALL_DIR")" && $EUID -ne 0 ]]; then
            command -v sudo >/dev/null 2>&1 || die "no permission to remove ${INSTALL_DIR} and sudo unavailable"
            use_sudo="sudo"
        fi
        run "${use_sudo} rm -rf $(printf '%q' "$INSTALL_DIR")"
        log_ok "removed ${INSTALL_DIR}"
    else
        log_warn "${INSTALL_DIR} does not exist; skipping directory removal"
    fi

    # Strip marker blocks from known rc files.
    local files=(
        "${HOME}/.bashrc"
        "${HOME}/.bash_profile"
        "${HOME}/.profile"
        "${HOME}/.zshrc"
        "/etc/profile.d/go.sh"
    )
    local f
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            if [[ ! -w "$f" && $EUID -ne 0 ]]; then
                log_warn "cannot modify $f without sudo; skipping"
                continue
            fi
            if grep -qF "$MARKER_BEGIN" "$f" 2>/dev/null; then
                log_info "stripping marker block from $f"
                strip_marker_block "$f"
                MODIFIED_FILES+=("$f")
            fi
        fi
    done

    # Fish config is a dedicated file we own; remove it entirely.
    local fish_conf="${HOME}/.config/fish/conf.d/go.fish"
    if [[ -f "$fish_conf" ]]; then
        log_info "removing $fish_conf"
        run "rm -f $(printf '%q' "$fish_conf")"
        MODIFIED_FILES+=("$fish_conf")
    fi

    log_ok "uninstall complete"
    printf '\nOpen a new shell so the stale environment variables are dropped.\n' >&2
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_summary() {
    printf '\n%s%sInstallation summary%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET" >&2
    printf '  Go version : %s\n' "$VERSION"        >&2
    printf '  Arch       : linux-%s\n' "$GO_ARCH"  >&2
    printf '  Install dir: %s\n' "$INSTALL_DIR"    >&2
    printf '  GOPATH     : %s\n' "$GOPATH_DIR"     >&2
    if (( ${#MODIFIED_FILES[@]} > 0 )); then
        printf '  Files touched:\n' >&2
        local f
        for f in "${MODIFIED_FILES[@]}"; do
            printf '    - %s\n' "$f" >&2
        done
    fi
    printf '\nOpen a new shell, or run:\n' >&2
    printf '    source ~/.bashrc   # or your shell'\''s rc file\n' >&2
    printf 'Then verify with:  go version\n\n' >&2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cleanup() {
    if [[ -n "${TMPDIR_PATH:-}" && -d "$TMPDIR_PATH" ]]; then
        rm -rf "$TMPDIR_PATH"
    fi
}
trap cleanup EXIT

main() {
    parse_args "$@"
    detect_platform

    if (( UNINSTALL )); then
        do_uninstall
        exit 0
    fi

    detect_distro
    resolve_version
    check_existing

    TMPDIR_PATH="$(mktemp -d -t install-go.XXXXXX)"
    download_and_verify
    install_tarball
    configure_shells
    print_summary
}

main "$@"
