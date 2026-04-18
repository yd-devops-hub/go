# 02 - golangci-lint

Notes and commands used while learning `golangci-lint`.

## Commands

Install `golangci-lint` into your `GOPATH/bin` directory. The installer script downloads the specified version (`v2.11.4`) and places the binary at `$(go env GOPATH)/bin`, which should be on your `PATH` so the command is available globally.

```bash
curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b $(go env GOPATH)/bin v2.11.4
```

Verify the installation by printing the installed version.

```bash
golangci-lint --version
```

## Next steps

Initialize a new Go module in this directory so we have a module to lint.

```bash
go mod init github.com/yd-devops-hub/go/learnings/02-golangci-lint
```

Create a `main.go` file with some sample code. Here we use `logrus` so that `go mod tidy` will add a real dependency and give the linter something meaningful to check.

```go
package main

import (
	"github.com/sirupsen/logrus"
)

func main() {
	logrus.Info("Hello! This is my first Go program.")
}
```

Resolve and download dependencies, updating `go.mod` and `go.sum`.

```bash
go mod tidy
```

Run `golangci-lint` against the module. By default it runs an opinionated set of linters (such as `errcheck`, `govet`, `staticcheck`, `ineffassign`, and `unused`) on every Go package in the current directory tree and reports any issues it finds.

```bash
golangci-lint run
```

Auto-format the Go source files in the module using the formatters configured in `golangci-lint` (e.g. `gofmt`, `goimports`). This rewrites files in place to match the expected style.

```bash
golangci-lint fmt
```

