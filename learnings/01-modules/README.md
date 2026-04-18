# 01 - Go Modules

Notes and commands used while learning Go modules.

## Commands

Initialize a new Go module in the current directory. This creates a `go.mod` file that tracks the module path and its dependencies.

```bash
go mod init github.com/yd-devops-hub/go/learnings/01-modules
```

Add `logrus` as a dependency. `go get` downloads the package, records it in `go.mod`, and updates `go.sum` with checksums for the resolved versions (including transitive deps like `golang.org/x/sys`).

```bash
go get github.com/sirupsen/logrus
```
