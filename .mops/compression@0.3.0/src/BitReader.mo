import Array "mo:base@0/Array";
import Debug "mo:base@0/Debug";
import Nat "mo:base@0/Nat";
import Nat8 "mo:base@0/Nat8";

import BitBuffer "mo:bitbuffer@1/BitBuffer";

module {
  public class BitReader() {
    var offset = 0;
    let bitbuffer = BitBuffer.new();
    var tailBits = 0;

    func is_valid(n : Nat) : Bool {
      n <= (bitbuffer.bitSize() - offset - tailBits : Nat);
    };

    public func peekBit() : Bool {
      if (not is_valid(1)) {
        Debug.trap("BitReader.peekBit(): out of bounds or empty");
      };

      bitbuffer.getBit(offset);
    };

    public func readBit() : Bool {
      let bit = peekBit();
      offset += 1;
      bit;
    };

    public func peekBits(n : Nat) : Nat {
      if (not is_valid(n)) {
        Debug.trap("BitReader.peekBits: out of bounds at offset");
      };

      bitbuffer.getBits(offset, n);
    };

    public func skipBits(n : Nat) {
      if (not is_valid(n)) {
        Debug.trap("BitReader.skipBits: out of bounds");
      };

      offset += n;
    };

    public func readBits(n : Nat) : Nat {
      let bits = peekBits(n);
      offset += n;
      bits;
    };

    public func peekByte() : Nat8 {
      if (not is_valid(8)) {
        Debug.trap("BitReader.peekByte: out of bounds");
      };

      let nbits = bitSize();

      if (nbits < 8) {
        Nat8.fromNat(bitbuffer.getBits(offset, nbits));
      } else {
        BitBuffer.getByte(bitbuffer, offset);
      };

    };

    public func readByte() : Nat8 {
      let byte = peekByte();

      offset += 8;
      byte;
    };

    public func peekBytes(nbytes : Nat) : [Nat8] {
      let pos = getPosition();

      let res = Array.tabulate(
        nbytes,
        func(_ : Nat) : Nat8 {
          readByte();
        },
      );

      setPosition(pos);
      res;
    };

    public func readBytes(nbytes : Nat) : [Nat8] {
      let min_bytes = Nat.min(nbytes, byteSize());

      Array.tabulate(
        min_bytes,
        func(_ : Nat) : Nat8 {
          readByte();
        },
      );
    };

    public func getPosition() : Nat { offset };
    public func setPosition(pos : Nat) { offset := pos };

    public func reset() { offset := 0 };

    public func clearRead() {
      bitbuffer.dropBits(offset);
      offset := 0;
    };

    public func clear() {
      offset := 0;
      tailBits := 0;
      bitbuffer.clear();
    };

    public func bitSize() : Nat {
      if (tailBits + offset < (bitbuffer.bitSize() : Nat)) {
        (bitbuffer.bitSize() - offset - tailBits : Nat);
      } else {
        0;
      };
    };

    public func byteSizeExact() : Nat {
      bitSize() / 8;
    };

    public func byteSize() : Nat {
      (bitSize() + 8 - 1) / 8;
    };

    public func byteAlign() {
      let size = bitSize();

      if (size % 8 != 0) {
        offset += (size % 8);
      };
    };

    public func addBytes(bytes : [Nat8]) {
      BitBuffer.addBytes(bitbuffer, bytes);
    };

    public func hideTailBits(n : Nat) {
      tailBits := n;
    };

    public func hiddenTailBits() : Nat {
      tailBits;
    };

    public func showTailBits() {
      tailBits := 0;
    };
  };

  public func fromBytes(bytes : [Nat8]) : BitReader {
    let reader = BitReader();
    reader.addBytes(bytes);
    reader;
  };
};
