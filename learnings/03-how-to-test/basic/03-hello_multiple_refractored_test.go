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
