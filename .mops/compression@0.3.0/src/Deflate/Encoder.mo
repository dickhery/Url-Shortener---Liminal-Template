import Buffer "mo:base@0/Buffer";
import Iter "mo:base@0/Iter";
import Option "mo:base@0/Option";
import Nat "mo:base@0/Nat";
import BitBuffer "mo:bitbuffer@1/BitBuffer";

import Block "Block";
import Symbol "Symbol";
import Lzss "../LZSS";
import LzssEncoder "../LZSS/Encoder";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  type BitBuffer = BitBuffer.BitBuffer;
  type Iter<A> = Iter.Iter<A>;
  type LzssEntry = Lzss.LzssEntry;
  type LzssEncoder = LzssEncoder.Encoder;
  type Symbol = Symbol.Symbol;

  public type DeflateOptions = {
    block_size : Nat;
    dynamic_huffman : Bool;
    lzss : ?LzssEncoder;
  };

  public class Encoder(
    bitbuffer : BitBuffer,
    options : DeflateOptions,
  ) {
    let block_type = switch (options.lzss) {
      case (null) { #Raw };
      case (?_) {
        if (options.dynamic_huffman) {
          #Dynamic({
            lzss = Option.get(options.lzss, Lzss.Encoder(null));
            block_limit = options.block_size;
          });
        } else {
          #Fixed({
            lzss = Option.get(options.lzss, Lzss.Encoder(null));
            block_limit = options.block_size;
          });
        };
      };
    };

    let block = Block.Block(block_type);

    public func encode_byte(byte : Nat8) {
      if (block.size() >= options.block_size) {
        flush(false);
      };

      block.add(byte);
    };

    public func encode(data : [Nat8]) {
      for (byte in data.vals()) {
        if (block.size() >= options.block_size) {
          // Debug.print("flushed block size: " # debug_show block.size());

          flush(false);
          // Debug.print("flushed block size: " # debug_show block.size());
        };

        block.add(byte);
      };

      // Debug.print("block size: " # debug_show block.size());
      // Debug.print("block limit: " # debug_show options.block_size);
    };

    type BlockEventHandler = (block_start : Nat, block_end : Nat) -> ();
    var new_block_event_handler : ?(BlockEventHandler) = null;

    public func set_new_block_event_handler(fn : BlockEventHandler) {
      new_block_event_handler := ?fn;
    };

    public func flush(is_final : Bool) {

      let size = bitbuffer.bitSize();
      bitbuffer.addBit(is_final);

      bitbuffer.addBits(2, Block.blockToNat(block_type));

      block.flush(bitbuffer);

      let block_start = size;
      let block_end = bitbuffer.bitSize();

      ignore do ? {
        new_block_event_handler! (block_start, block_end);
      };
    };

    public func clear() {
      block.clear();
    };

    public func finish() : BitBuffer {
      flush(true);
      clear();
      return bitbuffer;
    };
  };
};
