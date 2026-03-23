/// A Buffer for bit-level and byte-level manipulation.

import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Int8 "mo:base/Int8";
import Int16 "mo:base/Int16";
import Int32 "mo:base/Int32";
import Int64 "mo:base/Int64";

import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";

import BufferDeque "mo:buffer-deque/BufferDeque";

import { divCeil; int_represented_as_nat } "internal/utils";

module {
    type Buffer<A> = Buffer.Buffer<A>;
    type Iter<A> = Iter.Iter<A>;

    let BYTE = 8;

    public class BitBuffer(init_bits : Nat) {
        // TODO: Support little endian
        // var big_endian : Bool = true;

        let init_capacity = divCeil(init_bits, BYTE);

        let buffer = BufferDeque.BufferDeque<Nat8>(init_capacity);
        var total_bits : Nat = 0;

        var dropped_bits : Nat = 0;

        /// Returns the number of bits in the buffer
        public func bitSize() : Nat { total_bits - dropped_bits };

        /// Returns the max number of bits the buffer can hold without resizing
        public func bitCapacity() : Nat {
            (buffer.capacity() * BYTE) - dropped_bits;
        };

        /// Returns the number of bytes in the buffer
        public func byteSize() : Nat { divCeil(bitSize(), BYTE) };

        /// Returns the max number of bytes the buffer can hold without resizing
        public func byteCapacity() : Nat { divCeil(bitCapacity(), BYTE) };

        /// Returns the number of bits that match the given bit
        public func bitcount(bit : Bool) : Nat {
            var cnt = 0;

            for (byte in buffer.vals()) {
                cnt += Nat8.toNat(Nat8.bitcountNonZero(byte));
            };

            if (bit) { cnt } else { total_bits - cnt };
        };

        /// Adds a single bit to the bitbuffer
        public func addBit(bit : Bool) {
            let (byte_index, bit_index) = get_pos(total_bits);

            if (byte_index < buffer.size()) {
                let byte = buffer.get(byte_index);

                let new_byte = if (bit) {
                    Nat8.bitset(byte, bit_index);
                } else {
                    Nat8.bitclear(byte, bit_index);
                };

                buffer.put(byte_index, new_byte);

            } else {
                buffer.addBack(if (bit) 1 else 0);
            };

            total_bits += 1;
        };

        /// Adds the given bits to the bitbuffer
        public func addBits(n : Nat, bits : Nat) {
            var var_bits = bits;
            var nbits = n;
            let nbytes = divCeil(nbits, BYTE);

            let offset = total_bits % BYTE;
            let overflow = (BYTE - offset) : Nat;

            let len = Nat.min(nbits, overflow);
            var curr = Nat8.fromNat(var_bits % (2 ** len)) << Nat8.fromNat(offset);

            if (offset != 0) {
                let prev = switch (BufferDeque.peekBack(buffer)) {
                    case (?x) x;
                    case (null) {
                        let zero : Nat8 = 0;
                        buffer.addBack(zero);
                        zero;
                    };
                };

                buffer.put(buffer.size() - 1, prev | curr);
                var_bits /= (2 ** len);

                nbits -= len;
            };

            while (nbits > 0) {
                let len = Nat.min(nbits, BYTE);
                let next_byte = Nat8.fromNat(var_bits % (2 ** len));
                var_bits /= (2 ** len);
                buffer.addBack(next_byte);
                nbits -= len;
            };

            total_bits += n;
        };

        func get_pos(i : Nat) : (Nat, Nat) {
            let index = i + dropped_bits;
            (index / BYTE, index % BYTE);
        };

        /// Returns the bit at the given index as a `Bool`
        public func getBit(i : Nat) : Bool {
            let (byte_index, bit_index) = get_pos(i);

            if (byte_index >= buffer.size()) {
                Debug.trap("BitBuffer getBit(): Cannot get bit outside of the buffer");
            };

            let byte = buffer.get(byte_index);
            Nat8.bittest(byte, bit_index);
        };

        public func getBitsWithPotentialPartialEnd(i: Nat, bit_width: Nat) : Nat {
            if (i >= bitSize()) {
                Debug.trap("BitBuffer getBits(): Cannot get bits outside of the buffer");
            };

            let size = bitSize();

            if (i + bit_width > size) {
                let n = (size - i) : Nat;

                return getBits(i, n);
            };
            
            getBits(i, bit_width);
        };
 
        /// Returns the bits at the given index as a `Nat`
        public func getBits(i : Nat, n : Nat) : Nat {
            let (byte_index, bit_index) = get_pos(i);

            if (bit_index + n > bitSize()) {
                Debug.trap("BitBuffer getBits(): Cannot get more bits than the buffer contains");
            };

            let top_segment_len = Nat.min(n, BYTE - bit_index);
            let mask = 0xFF << Nat8.fromNat(bit_index);
            let masked = (buffer.get(byte_index) & mask);
            let read = Nat8.toNat(masked >> Nat8.fromNat(bit_index));
            var bits = read % (2 ** top_segment_len);

            var len = top_segment_len;

            var j = 1;
            while ((n - len : Nat) >= BYTE) {
                let byte = Nat8.toNat(buffer.get(byte_index + j));
                bits += byte * (2 ** len);
                len += BYTE;
                j += 1;
            };

            let diff = (n - len) : Nat;

            if (diff > 0) {
                let byte = Nat8.toNat(buffer.get(byte_index + j)) % (2 ** diff);
                bits += byte * (2 ** len);
            };

            bits;
        };

        /// Drops the first bit from the buffer.
        public func dropBit() : Bool {

            if (bitSize() == 0) {
                Debug.trap("BitBuffer dropBit(): Cannot drop bit from empty buffer");
            };

            let val = getBit(0);

            if (dropped_bits + 1 == BYTE) {
                ignore buffer.popFront();
                dropped_bits := 0;
                total_bits -= BYTE;
            } else {
                dropped_bits += 1;
            };

            val;
        };

        /// Drops the first `n` bits from the bitbuffer.
        /// Trap if `n` is greater than the number of bits in the bitbuffer.
        public func dropBits(n : Nat) {
            if (n > bitSize()) {
                Debug.trap("BitBuffer dropBits(): Cannot drop more bits than the buffer contains");
            };

            var nbits = n;

            if (nbits + dropped_bits >= BYTE) {
                ignore buffer.popFront();
                nbits -= (BYTE - dropped_bits);
                total_bits -= BYTE;
            };

            while (nbits >= BYTE) {
                ignore buffer.popFront();
                nbits -= BYTE;
                total_bits -= BYTE;
            };

            // The `dropped_bits` var gets subtracted from the `total_bits` in the `bitSize` method
            dropped_bits := nbits;
        };

        /// Flips all the bits in the buffer
        public func invert() {
            var i = 0;

            while (i < buffer.size()) {
                let byte = buffer.get(i);
                let new_byte = Nat8.bitnot(byte);
                buffer.put(i, new_byte);
                i += 1;
            };
        };

        public func clear() {
            buffer.clear();
            total_bits := 0;
            dropped_bits := 0;
        };

        /// Returns an iterator over the bits in the buffer
        public func bits() : Iter<Bool> {
            Iter.map(
                Iter.range(1, bitSize()),
                func(i : Nat) : Bool = getBit(i - 1),
            );
        };

        /// Returns an iterator over the bytes in the buffer
        public func bytes() : Iter<Nat8> { buffer.vals() };

        /// Aligns the buffer to the next byte boundary
        public func byteAlign() {
            let offset = total_bits % BYTE;

            if (offset != 0) {
                total_bits += BYTE - offset;
            };
        };
    };

    // ======================== Constructors ========================

    /// Initializes an empty bitbuffer
    public func new() : BitBuffer { BitBuffer(0) };

    /// Initializes a bitbuffer with the given byte capacity
    public func withByteCapacity(byte_capacity : Nat) : BitBuffer {
        BitBuffer(byte_capacity * BYTE);
    };

    /// Initializes a bitbuffer with `bit_capacity` bits and fills it with `ones` if `true` or `zeros` if `false`.
    public func init(bit_capacity : Nat, ones : Bool) : BitBuffer {
        let bitbuffer = BitBuffer(bit_capacity);
        var capacity = bit_capacity;

        let byte = if (ones) { 0xFF } else { 0x00 };

        while (capacity > 0) {
            let nbits = Nat.min(capacity, BYTE);
            bitbuffer.addBits(nbits, byte);
            capacity -= nbits;
        };

        bitbuffer;
    };

    /// Initializes a bitbuffer with `bit_capacity` bits and fills it with the bits returned by the function `f`.
    public func tabulate(bit_capacity : Nat, f : (Nat) -> Bool) : BitBuffer {
        let bitbuffer = BitBuffer(bit_capacity);

        for (i in Iter.range(1, bit_capacity)) {
            bitbuffer.addBit(f(i - 1));
        };

        bitbuffer;
    };

    /// Checks if the bits in the buffer are byte aligned
    public func isByteAligned(bitbuffer : BitBuffer) : Bool {
        bitbuffer.bitSize() % 8 == 0;
    };

    /// Returns the number of bits that are set to `true` or `1` in the buffer
    public func bitcountNonZero(bitbuffer : BitBuffer) : Nat {
        bitbuffer.bitcount(true);
    };

    // ========================== Byte operations ==================================

    public func addByte(bitbuffer : BitBuffer, byte : Nat8) {
        bitbuffer.addBits(BYTE, Nat8.toNat(byte));
    };

    public func getByte(bitbuffer : BitBuffer, bit_index : Nat) : Nat8 {
        Nat8.fromNat(bitbuffer.getBitsWithPotentialPartialEnd(bit_index, BYTE));
    };

    public func getFullByte(bitbuffer : BitBuffer, bit_index : Nat) : Nat8 {
        Nat8.fromNat(bitbuffer.getBits(bit_index, BYTE));
    };

    public func dropByte(bitbuffer : BitBuffer) = bitbuffer.dropBits(BYTE);

    // ========================== Bytes operations ==================================

    public func fromBytes(bytes : [Nat8]) : BitBuffer {
        let bitbuffer = withByteCapacity(bytes.size());
        addBytes(bitbuffer, bytes);
        bitbuffer;
    };

    public func addBytes(bitbuffer : BitBuffer, bytes : [Nat8]) {
        for (byte in bytes.vals()) {
            addByte(bitbuffer, byte);
        };
    };

    public func addBytesIter(bitbuffer : BitBuffer, bytes : Iter<Nat8>) {
        for (byte in bytes) {
            addByte(bitbuffer, byte);
        };
    };

    public func getBytes(bitbuffer : BitBuffer, bit_index : Nat, n : Nat) : [Nat8] {
        Array.tabulate(
            n,
            func(i : Nat) : Nat8 {
                getByte(bitbuffer, bit_index + (i * BYTE));
            },
        );
    };

    public func getFullBytes(bitbuffer : BitBuffer, bit_index : Nat, n : Nat) : [Nat8] {
        Array.tabulate(
            n,
            func(i : Nat) : Nat8 {
                getFullByte(bitbuffer, bit_index + (i * BYTE));
            },
        );
    };

    public func dropBytes(bitbuffer : BitBuffer, n : Nat){
        for (_ in Iter.range(1, n)) {
            dropByte(bitbuffer);
        };
    };

    // ========================== Nat8 operations ==================================

    public func addNat8(bitbuffer : BitBuffer, nat8 : Nat8) = addByte(bitbuffer, nat8);

    public func getNat8(bitbuffer : BitBuffer, bit_index : Nat) : Nat8 = getByte(bitbuffer, bit_index);

    public func dropNat8(bitbuffer : BitBuffer) = dropByte(bitbuffer);

    // ========================== Nat16 operations ==================================
    public func addNat16(bitbuffer : BitBuffer, nat16 : Nat16) {
        bitbuffer.addBits(BYTE * 2, Nat16.toNat(nat16));
    };

    public func getNat16(bitbuffer : BitBuffer, bit_index : Nat) : Nat16 {
        Nat16.fromNat(bitbuffer.getBits(bit_index, BYTE * 2));
    };

    public func dropNat16(bitbuffer : BitBuffer)  = bitbuffer.dropBits(BYTE * 2);

    // ========================== Nat32 operations ==================================

    public func addNat32(bitbuffer : BitBuffer, nat32 : Nat32) {
        bitbuffer.addBits(BYTE * 4, Nat32.toNat(nat32));
    };

    public func getNat32(bitbuffer : BitBuffer, bit_index : Nat) : Nat32 {
        Nat32.fromNat(bitbuffer.getBits(bit_index, BYTE * 4));
    };

    public func dropNat32(bitbuffer : BitBuffer) = bitbuffer.dropBits(BYTE * 4);

    // ========================== Nat64 operations ==================================
    public func addNat64(bitbuffer : BitBuffer, nat64 : Nat64) {
        bitbuffer.addBits(BYTE * 8, Nat64.toNat(nat64));
    };

    public func getNat64(bitbuffer : BitBuffer, bit_index : Nat) : Nat64 {
        Nat64.fromNat(bitbuffer.getBits(bit_index, BYTE * 8));
    };

    public func dropNat64(bitbuffer : BitBuffer) = bitbuffer.dropBits(BYTE * 8);

    public func addInt8(bitbuffer : BitBuffer, int8 : Int8) {
        bitbuffer.addBits(
            BYTE,
            int_represented_as_nat(Int8.toInt(int8), BYTE),
        );
    };

    public func addInt16(bitbuffer : BitBuffer, int16 : Int16) {
        bitbuffer.addBits(
            BYTE * 2,
            int_represented_as_nat(Int16.toInt(int16), BYTE * 2),
        );
    };

    public func addInt32(bitbuffer : BitBuffer, int32 : Int32) {
        bitbuffer.addBits(
            BYTE * 4,
            int_represented_as_nat(Int32.toInt(int32), BYTE * 4),
        );
    };

    public func addInt64(bitbuffer : BitBuffer, int64 : Int64) {
        bitbuffer.addBits(
            BYTE * 8,
            int_represented_as_nat(Int64.toInt(int64), BYTE * 8),
        );
    };
};
