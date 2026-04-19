package main

import "testing"

func TestHello(t *testing.T) {
	got := Hello("Yashraj")
	want := englishHelloPrefix + " Yashraj"

	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
}
