import Array "mo:base@0/Array";
import Buffer "mo:base@0/Buffer";
import Debug "mo:base@0/Debug";
import Deque "mo:base@0/Deque";
import Nat "mo:base@0/Nat";
import Iter "mo:base@0/Iter";

import BitBuffer "mo:bitbuffer@1/BitBuffer";
import Itertools "mo:itertools@0/Iter";

import Lzss "../LZSS";
import Symbol "Symbol";

import { nat_to_le_bytes; INSTRUCTION_LIMIT } "../utils";

module {
  type BitBuffer = BitBuffer.BitBuffer;
  type Symbol = Symbol.Symbol;
  type Iter<A> = Iter.Iter<A>;

  public let NO_COMPRESSION_MAX_BLOCK_SIZE = 65535;

  public type BlockType = {
    #Raw;
    #Fixed : {
      lzss : Lzss.Encoder;
      block_limit : Nat;
    };
    #Dynamic : {
      lzss : Lzss.Encoder;
      block_limit : Nat;
    };
  };

  public func blockToNat(blockType : BlockType) : Nat {
    switch blockType {
      case (#Raw) 0;
      case (#Fixed(_)) 1;
      case (#Dynamic(_)) 2;
    };
  };

  public func natToBlock(byte : Nat) : BlockType {
    switch byte {
      case (0) (#Raw);
      case (1) {
        #Fixed({
          lzss = Lzss.Encoder(null);
          block_limit = INSTRUCTION_LIMIT;
        });
      };
      case (2) {
        #Dynamic({
          lzss = Lzss.Encoder(null);
          block_limit = INSTRUCTION_LIMIT;
        });
      };
      case (_) Debug.trap("Invalid block type");
    };
  };

  public type BlockInterface = {
    size : () -> Nat;
    append : ([Nat8]) -> ();
    add : (Nat8) -> ();
    flush : (BitBuffer) -> ();
    clear : () -> ();
  };

  public func Block(block_type : BlockType) : BlockInterface {
    switch block_type {
      case (#Raw) Raw();
      case (#Fixed({ lzss; block_limit })) {
        Compress(
          lzss,
          Symbol.FixedHuffmanCodec(),
          block_limit,
        );
      };
      case (#Dynamic({ lzss; block_limit })) {
        Compress(
          lzss,
          Symbol.DynamicHuffmanCodec(),
          block_limit,
        );
      };
    };
  };

  public class Raw() {
    var deque = Deque.empty<Nat8>();
    var input_size = 0;
    var byte_aligned = false;

    public func size() : Nat { input_size };

    public func add(byte : Nat8) {
      input_size += 1;
      deque := Deque.pushBack<Nat8>(deque, byte);
    };

    public func append(bytes : [Nat8]) {
      for (byte in bytes.vals()) {
        add(byte);
      };
    };

    public func flush(bitbuffer : BitBuffer) {
      if (not byte_aligned) {
        bitbuffer.byteAlign();
        byte_aligned := true;
      };

      let size = Nat.min(NO_COMPRESSION_MAX_BLOCK_SIZE, input_size);

      let size_as_bytes = nat_to_le_bytes(size, 2);
      BitBuffer.addBytes(bitbuffer, size_as_bytes);

      let bitnot_size_as_bytes = Array.map<Nat8, Nat8>(size_as_bytes, func(x : Nat8) { ^x });
      BitBuffer.addBytes(bitbuffer, bitnot_size_as_bytes);

      for (i in Iter.range(0, size - 1)) {
        let ?(byte, xs) = Deque.popFront<Nat8>(deque) else { return };
        deque := xs;
        input_size -= 1;
        BitBuffer.addByte(bitbuffer, byte);
      };
    };

    public func clear() {
      input_size := 0;
      deque := Deque.empty<Nat8>();
      byte_aligned := false;
    };
  };

  public class Compress(lzss : Lzss.Encoder, huffman : Symbol.HuffmanCodec, _ : Nat) {
    var input_size = 0;
    var compressed_symbols = Buffer.Buffer<Symbol>(8);
    let sink = {
      add = func(symbol : Lzss.LzssEntry) {
        compressed_symbols.add(symbol);
      };
    };

    public func size() : Nat {
      return input_size;
    };

    public func add(byte : Nat8) : () {
      input_size += 1;
      lzss.encode_byte(byte, sink);
    };

    public func append(bytes : [Nat8]) {
      input_size += bytes.size();
      lzss.encode(bytes, sink);
    };

    func refresh() {
      input_size := 0;
      compressed_symbols.clear();
    };

    public func clear() {
      lzss.clear();
      compressed_symbols.clear();
      input_size := 0;
    };

    public func flush(bitbuffer : BitBuffer) {
      lzss.flush(sink);

      let used_symbols = Itertools.add(
        compressed_symbols.vals(),
        #EndOfBlock,
      );

      let symbol_encoder_rs = huffman.build(used_symbols);

      let #ok(symbol_encoder) = symbol_encoder_rs else {
        return;
      };

      ignore huffman.save(bitbuffer, symbol_encoder);

      for (symbol in compressed_symbols.vals()) {
        symbol_encoder.encode(bitbuffer, symbol);
      };

      symbol_encoder.encode(bitbuffer, #EndOfBlock);

      refresh();
    };

  };
};
