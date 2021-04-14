# StashTable
Concurrent hash table for Nim. Excellent way to safely share arbitrary data between multiple threads.

## Example

```nim
# nim c -r --gc:orc --threads:on example.nim
import os, random, stashtable

type SharedData = StashTable[string, seq[string], 100]

proc threading(d: tuple[t: int, shareddata: SharedData]) =
  for i in 0 .. 10:
    sleep(rand(10))
    d.shareddata.withValue("somekey"): value[].add($d.t & "->" & $i)

let shareddata = newStashTable[string, seq[string], 100]()
shareddata.insert("somekey", @[])

var threads: array[2, Thread[tuple[t: int, shareddata: SharedData]]]
for i in 0 .. 1: createThread(threads[i], threading, (i, shareddata))
joinThreads(threads)
echo shareddata
```

## Installation

latest stable release (1.2.1):
`nimble install StashTable`

## Documentation
https://olliNiinivaara.github.io/StashTable/

## Tests and benchmarking

https://github.com/olliNiinivaara/StashTable/blob/master/tests/testing.md