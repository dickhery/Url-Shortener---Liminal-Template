import Array "mo:base@0/Array";
import Buffer "mo:base@0/Buffer";
import Debug "mo:base@0/Debug";
import Option "mo:base@0/Option";
import Result "mo:base@0/Result";

import BitReader "../BitReader";
import Block "Block";
import Symbol "Symbol";
import Lzss "../LZSS";
import { le_bytes_to_nat } "../utils";

module {
  type BitReader = BitReader.BitReader;
  type Result<A, B> = Result.Result<A, B>;
  type Symbol = Symbol.Symbol;

  public class Decoder(bitreader : BitReader, output_buffer : ?Buffer.Buffer<Nat8>) {
    var end_of_blocks = false;
    let buffer = Option.get(output_buffer, Buffer.Buffer<Nat8>(8));
    let lzss_decoder = Lzss.Decoder();

    public func decode() : Result<(), Text> {
      debug {
        if (end_of_blocks) { return #ok() };

        end_of_blocks := bitreader.readBit();
        let block_type = bitreader.readBits(2);

        let res = if (block_type == 0) {
          decode_non_compressed();
        } else if (block_type == 1) {
          decode_compressed(Symbol.FixedHuffmanCodec());
        } else if (block_type == 2) {
          decode_compressed(Symbol.DynamicHuffmanCodec());
        } else {
          #err("Invalid block type " # debug_show block_type);
        };

        switch (res) {
          case (#err(msg)) return #err(msg);
          case (#ok(_)) {};
        };

        if (bitreader.byteSize() > 32_000) {
          return decode();
        };
      };

      #ok();
    };

    func decode_non_compressed() : Result<(), Text> {
      debug {
        bitreader.byteAlign();
        let size_as_bytes = bitreader.readBytes(2);
        let size = le_bytes_to_nat(size_as_bytes);
        let bitnot_size = le_bytes_to_nat(bitreader.readBytes(2));
        let flipped_size = le_bytes_to_nat(
          Array.map(
            size_as_bytes,
            func(n : Nat8) : Nat8 { ^n },
          )
        );

        if (bitnot_size != flipped_size) {
          return #err("Invalid size at the start of a non-compressed block");
        };

        let data = bitreader.readBytes(size);

        for (byte in data.vals()) {
          buffer.add(byte);
        };
      };

      #ok();
    };

    func decode_compressed(huffman : Symbol.HuffmanCodec) : Result<(), Text> {
      let symbol_decoder_res = huffman.load(bitreader);

      let symbol_decoder = switch (symbol_decoder_res) {
        case (#ok(decoder)) decoder;
        case (#err(msg)) return #err(msg);
      };

      label _loop loop {
        let symbol_res = symbol_decoder.decode(bitreader);
        let symbol = switch (symbol_res) {
          case (#ok(symbol)) symbol;
          case (#err(msg)) return #err(msg);
        };

        switch (symbol) {
          case (#EndOfBlock) break _loop;
          case (#literal(literal)) lzss_decoder.decodeEntry(buffer, #literal(literal));
          case (#pointer(back_ref)) lzss_decoder.decodeEntry(buffer, #pointer(back_ref));
        };
      };

      #ok();
    };

    public func finish() : Result<(), Text> {
      if (bitreader.bitSize() > (8 * 8)) {
        let res = decode();

        switch (res) {
          case (#err(msg)) return #err(msg);
          case (#ok(_)) {};
        };
      };

      #ok();
    };
  };
};
