// A stand-in operator binary: the point is that it is a real Go binary that must
// end up in the image built for linux/amd64 regardless of the host.
package main

import "fmt"

func main() { fmt.Println("smoke operator") }
