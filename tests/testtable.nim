when not compileOption("threads"):
  {.fatal: "threads are not enabled".}

import ../src/stashtable, tables

import unittest
import random
from times import epochTime
from strutils import formatFloat, FloatFormatMode

const
  threadcount = 4
  runs = 8
  valuesize = 10
  testsize = 16384
  keyspace = testsize * 5


type Value = array[valuesize, int]

const value = block:
  var result: Value
  for i in 0 ..< valuesize: result[i] = i
  result

let
  stash = newStashTable[int, Value, testsize]()
  optistash = newStashTable[int, Value, testsize]()
  stdtable = newTable[int, Value](16384)

var
  keys: array[testsize, int]

template takeBenchmark(code: untyped): float =
  let epochstart = epochTime()
  code
  (epochTime() - epochstart) * 1000


proc upsertToStashTable(split: int) =
    for k in 0 .. keys.high:
      if k mod threadcount == split: stash[keys[k]] = value

proc upsertToStdTable(split: int) =
  let time = takeBenchmark:
    for k in 0 .. keys.high:
      if k mod threadcount != -1: stdtable[keys[k]] = value
  echo "StdLib Table ", formatFloat(time/testsize, ffDecimal, 5), " ms / upsert"

proc deleteFromStashTable(split: int) =
    for k in 0 .. keys.high:
      if k mod 5 == 0 and k mod threadcount == split: stash.del(keys[k])
      
proc deleteFromStdTable(split: int) =
  let time = takeBenchmark:
    for k in 0 .. keys.high:
      if k mod 5 == 0 and k mod threadcount != -1:
        stdtable.del(keys[k])
  echo "StdLib Table ", formatFloat(time/(testsize/5), ffDecimal, 5), " ms / delete"

var stasum = 0

proc iterateStashTableKeys() =
  let time = takeBenchmark:
    for (key , index) in stash.keys(): stasum += key 
  echo "StashTable   ", formatFloat(time, ffDecimal, 5), " ms, iterated all keys"

proc iterateStdTableKeys() =
  var sum = 0
  let time = takeBenchmark:
    for key in stdtable.keys: sum += key
  echo "StdLib Table ", formatFloat(time, ffDecimal, 5), " ms, iterated all keys"
  if stasum != sum:
    echo "Ke iteration does not compute!"
    quit(1)

proc iterateStashTableValues() =
  stasum = 0
  let time = takeBenchmark:
    for (key , index) in stash.keys():
      stash.withFound(key, index):
        stasum += value[0]
  echo "StashTable   ", formatFloat(time, ffDecimal, 5), " ms, iterated all values"

proc iterateStdTableValues() =
  var sum = 0
  let time = takeBenchmark:
    for value in stdtable.mvalues: sum += value[0]
  echo "StdLib Table ", formatFloat(time, ffDecimal, 5), " ms, iterated all values"
  if stasum != sum:
    echo "Value iteration does not compute!"
    quit(1)

var stashnotfounds: int
var stdnotfounds: int

proc searchFromStashTable(split: int) =
  for k in 0 .. keys.high:
    if k mod threadcount == split:
      if stash.findIndex(keys[k]) == NotInStash: discard stashnotfounds.atomicInc()

proc searchFromStdTable() =
  let time = takeBenchmark:
    for k in 0 .. keys.high:
      if k mod threadcount != -1:
        if not stdtable.hasKey(keys[k]): discard stdnotfounds.atomicInc()
  echo "StdLib Table ", formatFloat(time, ffDecimal, 5), " ms / search"
  if stashnotfounds != stdnotfounds:
    echo "Search does not compute!"
    quit(1)


proc doTests() =
  var thr: array[threadcount, Thread[int]]
  var time = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], upsertToStashTable, split)
    joinThreads(thr)
  var size = stash.len().float
  echo "StashTable   ", formatFloat(time/size, ffDecimal, 5), " ms / upsert"
  upsertToStdTable(3)
 
  time = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], deleteFromStashTable, split)
    joinThreads(thr)
  echo "StashTable   ", formatFloat(time/(testsize/5), ffDecimal, 5), " ms / delete"
  deleteFromStdTable(3)

  time = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], searchFromStashTable, split)
    joinThreads(thr)
  echo "StashTable   ", formatFloat(time/(testsize), ffDecimal, 5), " ms / search"
  searchFromStdTable()
    
  iterateStashTableKeys()
  iterateStdTableKeys()

  iterateStashTableValues()
  iterateStdTableValues()

  if not optistash.addAll(stash, false):
    echo "Addall does not compute"
    quit(1)

  for key in stdtable.keys:
    optistash.withValue(key):
      discard
    do:
      echo "Optistash does not compute!"
      quit(1)

  
echo "testsize: ", testsize
randomize()
test "testtable":
  for run in 1 .. runs:
    stash.clear()
    stdtable.clear()
    optistash.clear()
    stasum = 0
    for i in 0 .. keys.high: keys[i] = rand(keyspace)
    echo "-------------"
    echo "run ", run
    doTests()