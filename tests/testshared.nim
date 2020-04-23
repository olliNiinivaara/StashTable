when not compileOption("threads"):
  {.fatal: "threads are not enabled".}

import stashtable

import sharedtables

import unittest
import locks, random
from os import sleep  
from times import epochTime
from strutils import formatFloat, FloatFormatMode

const
  threadcount = 16
  runs = 4
  valuesize = 10000
  testsize = 8192
  keyspace = testsize * 5
  tablesize = testsize*2
  simulateio = 1

type Value = array[valuesize, int]

let stash = newStashTable[int, Value, tablesize]()

var
  splits: array[threadcount, tuple[start: int, stop: int]]
  keys: array[testsize, int]
  morekeys: array[testsize, int]
  sharedtable: SharedTable[int, Value]
  sharedtablelock: Lock

var newvalue {.threadvar.} : Value


template takeBenchmark(code: untyped): float =
  let epochstart = epochTime()
  code
  (epochTime() - epochstart) * 1000
       
proc insertToStashTable(split: int) =  
  for x in splits[split].start .. splits[split].stop:
    newvalue[0] = keys[x]
    discard stash.insert(keys[x], newvalue)
    
proc writeToStashTable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    stash.withValue(keys[x]):
      value[0] -= 1

proc workwithStashTable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    stash.withValue(keys[x]):
      sleep(simulateio)
      value[0] += 1000
         
proc deleteFromStashTable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    stash.del(keys[x])

#-----------------------

proc insertToSharedtable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    withlock(sharedtablelock):
      try:
        discard sharedtable.mget(keys[x])
      except:
        newvalue[0] = keys[x]
        sharedtable[keys[x]] = newvalue
    
proc writeToSharedtable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    sharedtable.withValue(keys[x], value):
      value[0] -= 1

proc workwithSharedtable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    sharedtable.withValue(keys[x], value):
      sleep(simulateio)
      value[0] += 1000
      
proc deleteFromSharedtable(split: int) =
  for x in splits[split].start .. splits[split].stop:
    sharedtable.del(keys[x])
   
proc benchmark() =
  var thr: array[threadcount, Thread[int]]
  var insert = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], insertToStashTable, split)
    joinThreads(thr)
  var size = stash.len().float
  echo "StashTable  ", formatFloat(insert/size, ffDecimal, 5), " ms / insert"
  insert = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], insertToSharedtable, split)
    joinThreads(thr)
  echo "Sharedtable ", formatFloat(insert/size, ffDecimal, 5), " ms / insert"
  echo ""
  var delthr: array[1+(threadcount div 4), Thread[int]]
  var del = takeBenchmark:
    for split in 0 .. delthr.high: createThread(delthr[split], deleteFromStashTable, split)    
    joinThreads(delthr)
  echo "StashTable  ", formatFloat(del/size, ffDecimal, 5), " ms / delete"
  del = takeBenchmark:
    for split in 0 .. delthr.high: createThread(delthr[split], deleteFromSharedtable, split)    
    joinThreads(delthr)
  echo "Sharedtable ", formatFloat(del/size, ffDecimal, 5), " ms / delete"
  echo ""
  var write = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], writeToStashTable, split)
    joinThreads(thr)
  echo "StashTable  ", formatFloat(write/size, ffDecimal, 5), " ms / write"
  write = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], writeToSharedtable, split)
    joinThreads(thr)
  echo "Sharedtable ", formatFloat(write/size, ffDecimal, 5), " ms / write"
  echo ""
  var work = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], workwithStashTable, split)
    joinThreads(thr)
  echo "StashTable  ", formatFloat(work/size, ffDecimal, 5), " ms / (", simulateio, " ms io / key)"
  work = takeBenchmark:
    for split in thr.low .. thr.high: createThread(thr[split], workwithSharedtable, split)
    joinThreads(thr)
  echo "Sharedtable ", formatFloat(work/size, ffDecimal, 5), " ms / (", simulateio, " ms io / key)"


proc doSomeRandomTestOperations(split: int) =
  var largestvalue = 0
  for x in splits[split].start .. splits[split].stop:
    case x mod 5
    of 0:
      newvalue[0] = x
      discard stash.upsert(morekeys[x], newvalue)
      sharedtable.mgetOrPut(morekeys[x], newvalue) = newvalue
    of 1:
      newvalue[0] = morekeys[x]
      discard stash.insert(morekeys[x], newvalue)
      withlock(sharedtablelock):
        try:
          discard sharedtable.mget(morekeys[x])
        except:
          sharedtable[morekeys[x]] = newvalue
    of 2:
      stash.withValue(keys[x]): value[0] *= 2
      sharedtable.withValue(keys[x], value): value[0] *= 2
    of 3:
      sharedtable.del(keys[x])
      stash.del(keys[x])
    of 4:      
      for (key , index) in stash.keys:
        stash.withFound(key, index):
          if value[0] > largestvalue:
            largestvalue = value[0]
    else: discard

        
proc crossCheck() =
  var largestvalue = 0
  for (key , index) in stash.keys():
    stash.withFound(key, index):
      if value[0] > largestvalue: largestvalue = value[0]
      try:
        let svalue = sharedtable.mget(key)
        if value[0] != svalue[0]:
          echo "key ", key, " has value ", value[0], " in stash, but ", svalue[0], " in SharedTable"
          if threadcount == 1: (echo "Fatal bug!"; doAssert false)
      except:
        echo "Key ", key, " in StashTable but not in SharedTable"
        if threadcount == 1: (echo "Fatal bug!"; doAssert false)
  for i in 0 .. keys.high:
    sharedtable.withValue(keys[i], svalue):
      stash.withValue(keys[i]):
        if value[0] != svalue[0]: echo "key ", keys[i], " has value ", value[0], " in stash, but ", svalue[0], " in SharedTable"
      do:
        echo "Key ", keys[i], " in SharedTable with value ", svalue[0], " but missing from StashTable"
        if threadcount == 1: (echo "Fatal bug!"; doAssert false)
  for i in 0 .. morekeys.high:
    sharedtable.withValue(morekeys[i], svalue):
      stash.withValue(morekeys[i]):
        if value[0] != svalue[0]: echo "key ", morekeys[i], " has value ", value[0], " in stash, but ", svalue[0], " in SharedTable"
      do:
        echo "Key ", morekeys[i], " in SharedTable with value ", svalue[0]," but missing from StashTable"
        if threadcount == 1: (echo "Fatal bug!"; doAssert false)


sharedtable.init(tablesize)
sharedtablelock.initLock()
assert(testsize > threadcount)
randomize()
let step = testsize div threadcount
for i in 0 ..< threadcount:
  splits[i].start = i * step
  splits[i].stop = i * step + step - 1
echo "threadcount: ", threadcount
echo "testsize: ", testsize
echo "tablesize: ", tablesize

test "sharedtest":
  for run in 1 .. runs:
    stash.clear()
    sharedtable.deinitSharedTable()
    sharedtable.init(tablesize)     
    for i in 0 .. keys.high: keys[i] = rand(keyspace)    
    echo "-------------"
    echo "run ", run
    benchmark()
    for i in 0 .. morekeys.high: morekeys[i] = rand(keyspace)
    var thr: array[threadcount, Thread[int]]
    for split in thr.low .. thr.high: createThread(thr[split], doSomeRandomTestOperations, split)
    joinThreads(thr)
    crosscheck()