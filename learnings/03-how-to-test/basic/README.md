# 03 - How to test

Notes and commands used while learning how to write tests in Go with the standard `testing` package.

## Creating a test with the `testing` package

Writing a test in Go is just like writing a function, with a few rules:

- It needs to be in a file with a name like `xxx_test.go`.
- The test function must start with the word `Test`.
- The test function takes one argument only: `t *testing.T`.
- To use the `*testing.T` type, you need to `import "testing"`, like we did with `fmt` in the other file.

Here is the function under test in `main.go`. It takes a `name` and returns the greeting from the shared `englishHelloPrefix` constant, optionally appending the name.

```go
package main

import "fmt"

const englishHelloPrefix = "Hello, world!!"

func Hello(name string) string {
	if name != "" {
		return englishHelloPrefix + " " + name
	}
	return englishHelloPrefix
}

func main() {
	fmt.Println(Hello("Yashraj"))
}
```

And the matching test in `hello_test.go`.

```go
package main

import "testing"

func TestHello(t *testing.T) {
	got := Hello()
	want := "Hello, world"

	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
}
```

## Grouping multiple tests with subtests (`t.Run`)

As the behaviour of a function grows, you often want to assert multiple cases. Instead of writing a separate top-level `TestXxx` function for each one, you can group related cases as **subtests** using `t.Run`.

Benefits of using `t.Run`:

- It keeps related cases together under a single parent test.
- Each subtest has its own descriptive name, which appears in the test output.
- You can run just one subtest from the command line using the `-run` flag.

Here is `hello_multiple_test.go`, which exercises `Hello` with both a name and an empty string:

```go
package main

import "testing"

func TestHelloMultiple(t *testing.T) {
	// test1
	t.Run("saying hello to people", func(t *testing.T) {
		got := Hello("Chris")
		want := englishHelloPrefix + " " + "Chris"

		if got != want {
			t.Errorf("got %q want %q", got, want)
		}
	})
	// test2
	t.Run("say 'Hello, world!!' when an empty string is supplied", func(t *testing.T) {
		got := Hello("")
		want := englishHelloPrefix

		if got != want {
			t.Errorf("got %q want %q", got, want)
		}
	})
}
```

A few things to note:

- Each subtest takes a name (a plain string) and a function with the same `func(t *testing.T)` signature as a normal test.
- Reusing the `englishHelloPrefix` constant from `main.go` keeps the test in sync with the production code: if the greeting ever changes, both the implementation and the expected values update together.

## Refactoring with a test helper and `t.Helper()`

Notice that both subtests above end with the exact same three lines:

```go
if got != want {
    t.Errorf("got %q want %q", got, want)
}
```

That duplication is a smell. We can pull it out into a small helper and call it from each subtest. Here is `03-hello_multiple_refractored_test.go`:

```go
package main

import "testing"

func TestHelloMultipleRefractored(t *testing.T) {
	// test1
	t.Run("saying hello to people", func(t *testing.T) {
		got := Hello("Chris")
		want := englishHelloPrefix + " " + "Chris"

		assertCorrectMessage(t, got, want)
	})
	// test2
	t.Run("say 'Hello, world!!' when an empty string is supplied", func(t *testing.T) {
		got := Hello("")
		want := englishHelloPrefix

		assertCorrectMessage(t, got, want)
	})
}

func assertCorrectMessage(t testing.TB, got, want string) {
	t.Helper()
	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
}
```

A few things to note about the refactor:

- `assertCorrectMessage` takes `t testing.TB` instead of `t *testing.T`. `testing.TB` is an interface that both `*testing.T` and `*testing.B` satisfy, so the same helper can be reused from tests *and* benchmarks.
- `t.Helper()` is needed to tell the test suite that this method is a helper. By doing this, when it fails, the line number reported will be in our function call (inside the subtest) rather than inside our test helper. This will help other developers track down problems more easily.
- The subtests now read as a simple "arrange / act / assert": compute `got`, compute `want`, then assert — with no duplicated `if`/`t.Errorf` boilerplate.

## Commands

Run the tests in the current package.

```bash
go test
```

Run the tests with verbose output so each subtest name is printed.

```bash
go test -v
```

Run only a specific test or subtest. The value passed to `-run` is a regular expression matched against the test name (use `/` to target a subtest).

```bash
go test -run TestHelloMultiple
go test -run TestHelloMultiple/saying_hello_to_people
```
