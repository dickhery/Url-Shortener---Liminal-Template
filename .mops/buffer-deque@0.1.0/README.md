## BufferDeque
A Buffer with the functionality of a Deque for efficient insertion and deletion at both ends.

## Installation
Install the package with [mops](https://mops.one/):
```bash
mops add buffer-deque
```

## Usage
```motoko
import BufferDeque "mo:buffer-deque/BufferDeque";

let buffer = BufferDeque.BufferDeque(8);
buffer.addFront(2);
buffer.addBack(3);
buffer.addFront(1);

assert BufferDeque.toArray(buffer) == [1, 2, 3];

assert buffer.popFront() == ?1;
assert buffer.popBack() == ?3;

assert buffer.get(0) == 2;
assert BufferDeque.toArray(buffer) == [2];
```

## Documentation
The documentation is available in the following formats:
- [markdown](https://github.com/NatLabs/BufferDeque/blob/main/docs/index.md)
- [web](https://natlabs.github.io/BufferDeque)
