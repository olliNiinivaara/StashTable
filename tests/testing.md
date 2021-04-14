## testshared

testshared.nim compares StashTable against [SharedTable](https://nim-lang.org/docs/sharedtables.html). You can benchmark different
aspects by modifying the consts in file.

Essentially, SharedTable will drastically slow down when reading or writing
takes some time (simulateio parameter in test.nim), while StashTable just keeps going.

Each benchmark run ends with a random sequence of operations executed on both tables
after which the table contents are compared.
There will nondeterministically be notifications that the contents do not align.
Explanation is that a context switch has happened when an operation was executed on
the other table but not yet on the other, and the other thread operated on the same key.
For example:
```
...
Thread 1:
Stashtable : op1-1: insert X
Thread 2:
Stashtable : op2-1: delete X
Sharedtable: op2.1: delete X
Thread 1:
Sharedtable: op1-1: insert X
...
```
This nondeterminism is not an implication that either StashTable or SharedTable has incorrect implementation (see below).

## testtable

testshared.nim compares StashTable against Nim stdlib's single-threaded [TableRef](https://nim-lang.org/docs/tables.html).

Essentially, StashTable is bit slower than Table, but searching for a key and iterating over all keys
are much faster with StashTable (because those operations do not need locking).

Unlike testshared, this test is totally deterministic and table contents always align.
Therefore this test shows the correctness of StashTable implementation.
