## Augmented Btrees
This library offers various B-tree implementations, each optimized for specific use cases when storing and managing sorted key-value pairs. These variants represent different trade-offs in features and performance.

**Supported B-tree variants:**
- [x] B+ Tree ([docs](https://mops.one/augmented-btrees/docs/BpTree/lib#new))
- [ ] Max Value B+ Tree ([docs](https://mops.one/augmented-btrees/docs/MaxBpTree/lib#new)) `in-progress`

### Usage
- **Import the library**
  
```motoko
    import { BpTree; MaxBpTree; Cmp } "mo:augmented-btrees";
```

- **Creating a new B+ Tree**
    - Specify the desired `order` of the tree, which determines the maximum number of entries a single leaf node can hold. The order can be any number in this range [4, 8, 16, 32, 64, 128, 256, 516] with the default being 32. 

```motoko
    let bptree = BpTree.new(?32);
```

- **Comparator Function**
  - This library replaces the default comparator function with a more performant `Cmp` module that returns an `Int8` type for comparisons, which requires less overhead compared to the `Order` type.
  - The `Cmp` module provides functions for various primitive types in motoko. 
  - Here's an example of a B+Tree that stores and compares `Char` keys.
    ```motoko
        import { BpTree; Cmp } "mo:augmented-btrees";
        
        let arr = [('A', 0), ('B', 1), ('C', 2), ('D', 3), ('E', 4)];

        let bptree = BpTree.fromArray(arr, Cmp.Char, null);

    ```
  - You can define your own comparator functions for custom types. The comparator function must return either of these `Int8` values:
    - `0` if the two values are equal
    - `1` if the first value is greater than the second value
    - `-1` if the first value is less than the second value

- **Examples of operations on a B+ Tree**
```motoko
    let arr = [('A', 0), ('B', 1), ('C', 2), ('D', 3), ('E', 4)];
    let bptree = BpTree.fromArray(arr, Cmp.Char, null);

    assert BpTree.get(bptree, 'A') == ?0;

    ignore BpTree.insert(bptree, 'F', 5);
    assert Iter.toArray(BpTree.vals(bptree)) == ['A', 'B', 'C', 'D', 'E', 'F'];

    // replace
    assert BpTree.insert(bptree, 'C', 33) == ?3;

    assert BpTree.remove(bptree, Cmp.Char, 'C') == ?33;
    assert BpTree.toArray(bptree) == [('A', 0), ('B', 1), ('D', 3), ('E', 4), ('F', 5)];

    assert BpTree.min(bptree, Cmp.Char) == ?('A', 0);
    assert BpTree.max(bptree, Cmp.Char) == ?('F', 5);

    // get sorted position of a key
    assert BpTree.getIndex(bptree, Cmp.Char, 'A') == 0;

    // get the key and value at a given position
    assert BpTree.getFromIndex(bptree, 0) == ('A', 0);
```

- **Iterating over a B+ Tree**
  - All iterators implemented in this library are of the type `RevIter` and are reversible. 
  - An iterator can be created from a B+ Tree using any of these functions: `entries()`, `keys()`, `vals()`, `scan()`, or `range()`. 
  - The iterator can be reversed by calling the `.rev()` function on the iterator.
    > For more details on reversible iterators, refer to the [itertools library documentation](https://mops.one/itertools/docs/RevIter)

```motoko
    let entries = BpTree.entries(bptree);
    assert Iter.toArray(entries.rev()) == [('E', 4), ('D', 3), ('C', 2), ('B', 1), ('A', 0)];

    // search for elements bounded by the given keys
    let results = BpTree.scan(bptree, Cmp.Char, ?'B', ?'D');
    assert Iter.toArray(results) == [('B', 1), ('C', 2), ('D', 3)];
    
    let results2 = BpTree.scan(bptree, Cmp.Char, ?'A', ?'C');
    assert Iter.toArray(results2.rev()) == [('C', 2), ('B', 1), ('A', 0)];

    // retrieve elements by their **index**
    let range1 = BpTree.range(bptree, 2, 4);
    assert Iter.toArray(range1) == [('C', 2), ('D', 3), ('E', 4)];

    // retrieve the next 3 elements after a given key
    let index_of_B = BpTree.getIndex(bptree, Cmp.Char, 'B');
    assert index_of_B == 1;
    
    let range2 = BpTree.range(bptree, index_of_B + 1, indexB + 3);
    assert Iter.toArray(range2) == [('C', 2), ('D', 3), ('E', 4)];
```

### Benchmarks
Benchmarking the performance with 10k entries


#### Comparing RBTree, BTree and B+Tree (BpTree)

**Instructions**

|            |    insert() |   replace() |      get() |  entries() |     scan() |    remove() |
| :--------- | ----------: | ----------: | ---------: | ---------: | ---------: | ----------: |
| RBTree     | 105_236_358 | 103_166_554 | 44_269_891 | 17_795_354 |      ----- | 141_566_127 |
| BTree      | 114_964_951 |  83_757_726 | 78_246_105 | 10_944_900 | 24_351_645 | 130_728_937 |
| B+Tree     | 116_288_125 |  91_628_770 | 81_339_298 |  4_854_853 |  6_635_837 | 128_646_576 |
| Max B+Tree | 148_500_723 | 119_942_183 | 81_341_110 |  4_856_757 |  6_619_287 | 166_204_227 |

**Heap**

|            |  insert() | replace() |   get() | entries() |    scan() |    remove() |
| :--------- | --------: | --------: | ------: | --------: | --------: | ----------: |
| RBTree     | 9_051_828 | 8_268_692 |  12_960 | 1_889_036 |     8_904 | -15_479_980 |
| BTree      | 1_234_000 | 1_157_004 | 484_600 |   602_276 | 1_014_572 |   1_968_844 |
| B+Tree     |   735_132 |   613_804 | 213_800 |     9_084 |    31_424 |     213_524 |
| Max B+Tree | 1_183_672 |   778_164 | 213_800 |     9_084 |    31_424 |     627_036 |

#### Other B+Tree functions

**Instructions**

|                |      B+Tree |  Max B+Tree |
| :------------- | ----------: | ----------: |
| getFromIndex() |  68_084_521 |  73_059_451 |
| getIndex()     | 167_272_699 | 167_274_197 |
| getFloor()     |  79_745_701 |  79_747_291 |
| getCeiling()   |  79_746_354 |  79_748_036 |
| removeMin()    | 151_741_662 | 126_593_310 |
| removeMax()    | 115_662_568 |  71_610_769 |

**Heap**

|                |  B+Tree | Max B+Tree |
| :------------- | ------: | ---------: |
| getFromIndex() | 328_960 |    328_960 |
| getIndex()     | 586_764 |    586_764 |
| getFloor()     | 213_804 |    213_804 |
| getCeiling()   | 213_804 |    213_804 |
| removeMin()    | 213_864 |    487_516 |
| removeMax()    | 209_944 |    533_116 |