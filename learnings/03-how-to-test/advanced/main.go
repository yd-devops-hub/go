package main

import "fmt"

// const englishHelloPrefix = "Hello, "
// const spanishHelloPrefix = "Hola, "
// const frenchHelloPrefix = "Bonjour, "

const (
	spanish = "Spanish"
	french  = "French"

	englishHelloPrefix = "Hello, "
	spanishHelloPrefix = "Hola, "
	frenchHelloPrefix  = "Bonjour, "
)


func languageGreetPrefix(language string) (prefix string) {
	switch language {
	case "Spanish":
		prefix = spanishHelloPrefix
	case "French":
		prefix = frenchHelloPrefix
	default:
		prefix = englishHelloPrefix
	}
	return
}

func Hello(name string, language string) string {
	// if name != "" {
	// 	if language == "Spanish" {
	// 		return spanishHelloPrefix + name
	// 	}
	// 	if language == "French" {
	// 		return frenchHelloPrefix + name
	// 	}
	// 	return englishHelloPrefix + name
	// }
	// return englishHelloPrefix + "world!!"

	if name != "" {
		return languageGreetPrefix(language) + name
	}
	return languageGreetPrefix(language) + "world!!"
}

func main() {
	fmt.Println(Hello("Jerry", ""))
	fmt.Println(Hello("Jerry", "Spanish"))
	fmt.Println(Hello("Jerry", "French"))
}
