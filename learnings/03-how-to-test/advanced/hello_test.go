package main

import "testing"

func TestHelloMultiple(t *testing.T) {
	// test1
	t.Run("saying hello to people", func(t *testing.T) {
		got := Hello("Tom", "")
		want := englishHelloPrefix + "Tom"

		assertCorrectMessage(t, got, want)
	})
	// test2
	t.Run("say 'Hello, world!!' when an empty string is supplied", func(t *testing.T) {
		got := Hello("", "")
		want := englishHelloPrefix + "world!!"

		assertCorrectMessage(t, got, want)
	})
	// test3
	t.Run("say hello in Spanish", func(t *testing.T) {
		got := Hello("Tom", "Spanish")
		want := spanishHelloPrefix + "Tom"

		assertCorrectMessage(t, got, want)
	})
	// test4
	t.Run("say hello in French", func(t *testing.T) {
		got := Hello("Tom", "French")
		want := frenchHelloPrefix + "Tom"

		assertCorrectMessage(t, got, want)
	})
}

func assertCorrectMessage(t testing.TB, got, want string) {
	t.Helper()
	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
}
