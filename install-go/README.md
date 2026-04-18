# install-go.sh

A single self-contained Bash script that installs the Go toolchain on Linux
from the **official go.dev tarball**.

- Per-user install by default (`~/.local/go`, no sudo required)
- Optional system-wide install (`/usr/local/go`, official layout)
- Installs the latest stable Go by default, or any pinned version
- Auto-detects CPU architecture (amd64, arm64, armv6l, 386, riscv64, loong64, ppc64le, s390x)
- Verifies the SHA-256 checksum before extracting
- Wires up `GOROOT`, `GOPATH`, `GOBIN`, and `PATH` for **bash**, **zsh**, and **fish**
- Idempotent: re-running does not duplicate anything
- Clean `--uninstall` that removes both the install dir and the shell config
- Supports `--dry-run`

## Quick start

```bash
# Install the latest stable Go for the current user
./install-go.sh

# Then, open a new shell (or source your rc file) and verify:
go version
```

## Usage

```text
./install-go.sh [OPTIONS]

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
```

## Examples

```bash
# Pinned version, per-user install
./install-go.sh --version 1.22.5

# System-wide install (prompts for sudo)
./install-go.sh --system

# Custom prefix (Go will land at /opt/langs/go)
./install-go.sh --prefix /opt/langs

# Latest Go but put GOPATH somewhere custom
./install-go.sh --gopath ~/code/go

# See exactly what would happen without changing anything
./install-go.sh --dry-run

# Remove everything this script installed
./install-go.sh --uninstall
```

## Supported platforms

### Distros

Any Linux distro with `bash`, `tar`, `sha256sum`, and either `curl` or `wget`.
Tested conceptually against:

- Debian / Ubuntu / Mint / Pop!_OS
- Fedora / RHEL / CentOS Stream / Rocky / AlmaLinux
- Arch / Manjaro / EndeavourOS
- openSUSE / SLES
- Alpine (see musl note below)

### Architectures

| `uname -m`        | Go binary    |
| ----------------- | ------------ |
| `x86_64`          | `amd64`      |
| `aarch64`/`arm64` | `arm64`      |
| `armv6l`          | `armv6l`     |
| `armv7l`          | `armv6l` (Go only ships one ARM 32-bit build) |
| `i686`/`i386`     | `386`        |
| `riscv64`         | `riscv64`    |
| `loongarch64`     | `loong64`    |
| `ppc64le`         | `ppc64le`    |
| `s390x`           | `s390x`      |

### Shells

- **bash**: writes to `~/.bashrc` (and creates `~/.profile` for login shells if
  neither `~/.bash_profile` nor `~/.profile` exists).
- **zsh**: writes to `~/.zshrc` if zsh is installed or `~/.zshrc` already exists.
- **fish**: drops a dedicated file at `~/.config/fish/conf.d/go.fish` using
  fish-native `set -gx` syntax.
- **system-wide** (`--system` as root): additionally writes `/etc/profile.d/go.sh`.

## Alpine / musl libc

The official Go binaries are linked against glibc and will not run on musl
systems such as Alpine. The script detects musl and stops with an actionable
error. If you really want to try, pass `--force`. Otherwise use your package
manager:

```bash
sudo apk add go
```

## What gets added to your shell rc

A marker-guarded block (so re-runs and `--uninstall` can find it):

```bash
# >>> install-go.sh >>>
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
# ... PATH prepends, guarded against duplicates ...
# <<< install-go.sh <<<
```

The fish version uses `set -gx` and `contains` instead of `export` and the
`case` PATH check.

## Manual PATH setup (fallback)

If you pass `--no-shell-config` or want to wire things up yourself:

```bash
export GOROOT="$HOME/.local/go"        # or /usr/local/go for --system
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$GOROOT/bin:$GOBIN:$PATH"
```

For fish:

```fish
set -gx GOROOT $HOME/.local/go
set -gx GOPATH $HOME/go
set -gx GOBIN  $GOPATH/bin
set -gx PATH   $GOROOT/bin $GOBIN $PATH
```

## Uninstall

```bash
./install-go.sh --uninstall
```

This removes the install directory (`~/.local/go`, `/usr/local/go`, or your
`--prefix`/go), strips the marker block from `~/.bashrc`, `~/.bash_profile`,
`~/.profile`, `~/.zshrc`, and `/etc/profile.d/go.sh`, and deletes
`~/.config/fish/conf.d/go.fish`. Open a new shell afterward so the env vars
drop out.

## Notes

- Checksums are fetched from `https://dl.google.com/go/<file>.sha256` and
  verified with `sha256sum` before extraction.
- The latest version is resolved from `https://go.dev/VERSION?m=text`.
- If the same version is already installed, the script skips the download and
  just ensures shell config is up to date. Pass `--force` to reinstall.
- Any existing Go installed via your distro's package manager at `/usr/bin/go`
  is left alone; the new install takes precedence because its `bin` is
  prepended to `PATH`.
