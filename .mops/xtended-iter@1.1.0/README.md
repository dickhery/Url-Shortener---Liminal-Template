# Motoko Extended Iterator Library

[![MOPS](https://img.shields.io/badge/MOPS-xtended--iter-blue)](https://mops.one/xtended-iter)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/edjCase/motoko_iter/blob/main/LICENSE)

A Motoko library that extends the functionality of the base `Iter` module with additional utility functions for advanced iterator operations. This library provides enhanced iteration capabilities including chunking, grouping, sorting checks, partitioning, and peekable iterators.

**Note:** This is a fork of [Itertools](https://github.com/NatLabs/Itertools) by Tomi Jaga, but represents my own subjective take and has been updated for the base library redux.

## MOPS

```bash
mops add xtended-iter
```

To set up MOPS package manager, follow the instructions from the [MOPS Site](https://mops.one)

## IterX Module

### Chunking and Splitting

- `chunk<A>(iter, chunkSize)`: Split iterator into fixed-size chunks
- `splitAt<A>(iter, n)`: Split iterator at position n
- `unzip<A, B>(iter)`: Unzip iterator of tuples into two arrays

### Search and Find

- `findIndex<A>(iter, predicate)`: Find index of first matching element
- `findIndices<A>(iter, predicate)`: Find all indices of matching elements
- `nth<A>(iter, n)`: Get nth element from iterator
- `equal<A>(iter1, iter2, equalFn)`: Check if two iterators are equal

### Grouping and Partitioning

- `groupBy<A>(iter, predicate)`: Group consecutive elements by predicate
- `partition<A>(iter, predicate)`: Split iterator into two based on predicate

### Sorting and Ordering

- `isSorted<A>(iter, cmp)`: Check if iterator is sorted in ascending order
- `isSortedDesc<A>(iter, cmp)`: Check if iterator is sorted in descending order
- `minmax<A>(iter, cmp)`: Find minimum and maximum elements

### Array Operations

- `flattenArray<A>(nestedIter)`: Flatten iterator of arrays into single iterator

### Conversion

- `toPeekable<T>(iter)`: Convert regular iterator to peekable iterator

## PeekableIter Module

`PeekableIter<T>`: Iterator that allows peeking at next element without consuming it.

- `fromIter<T>(iter)`: Create peekable iterator from regular iterator
- `peek()`: View next element without consuming it
- `next()`: Consume and return next element
- `hasNext<T>(iter)`: Check if iterator has more elements
- `isNext<T>(iter, val, isEq)`: Check if next element equals given value

## API Reference

### IterX

```motoko
public func chunk<A>(iter : Iter.Iter<A>, chunkSize : Nat) : Iter.Iter<[A]>
public func equal<A>(iter1 : Iter.Iter<A>, iter2 : Iter.Iter<A>, isEq : (A, A) -> Bool) : Bool
public func findIndex<A>(iter : Iter.Iter<A>, predicate : (A) -> Bool) : ?Nat
public func findIndices<A>(iter : Iter.Iter<A>, predicate : (A) -> Bool) : Iter.Iter<Nat>
public func flattenArray<A>(nestedArray : Iter.Iter<[A]>) : Iter.Iter<A>
public func groupBy<A>(iter : Iter.Iter<A>, pred : (A) -> Bool) : Iter.Iter<([A], Bool)>
public func isSorted<A>(iter : Iter.Iter<A>, cmp : (A, A) -> Order.Order) : Bool
public func isSortedDesc<A>(iter : Iter.Iter<A>, cmp : (A, A) -> Order.Order) : Bool
public func minmax<A>(iter : Iter.Iter<A>, cmp : (A, A) -> Order.Order) : ?(A, A)
public func nth<A>(iter : Iter.Iter<A>, n : Nat) : ?A
public func partition<A>(iter : Iter.Iter<A>, f : (A) -> Bool) : (Iter.Iter<A>, Iter.Iter<A>)
public func splitAt<A>(iter : Iter.Iter<A>, n : Nat) : (Iter.Iter<A>, Iter.Iter<A>)
public func toPeekable<T>(iter : Iter.Iter<T>) : PeekableIter.PeekableIter<T>
public func unzip<A, B>(iter : Iter.Iter<(A, B)>) : ([A], [B])
```

### PeekableIter

```motoko
public type PeekableIter<T> = Iter.Iter<T> and {
    peek : () -> ?T;
};
public func fromIter<T>(iter : Iter.Iter<T>) : PeekableIter<T>
public func hasNext<T>(iter : PeekableIter<T>) : Bool
public func isNext<T>(iter : PeekableIter<T>, val : T, isEq : (T, T) -> Bool) : Bool
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
