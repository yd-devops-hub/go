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
