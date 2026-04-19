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
	// fmt.Println(Hello())
	// fmt.Println(Hello(""))
	fmt.Println(Hello("Yashraj"))
}
