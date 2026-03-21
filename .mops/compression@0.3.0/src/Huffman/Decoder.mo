import Array "mo:base@0/Array";
import Debug "mo:base@0/Debug";
import Nat "mo:base@0/Nat";
import Nat8 "mo:base@0/Nat8";
import Nat16 "mo:base@0/Nat16";
import Result "mo:base@0/Result";
import Iter "mo:base@0/Iter";
import Option "mo:base@0/Option";

import Common "Common";
import BitReader "../BitReader";
import BitBuffer "mo:bitbuffer@1/BitBuffer";

module {

  type Result<A, B> = Result.Result<A, B>;
  type BitBuffer = BitBuffer.BitBuffer;
  type BitReader = BitReader.BitReader;

  type Code = Common.Code;
  type BuilderInterface<A> = Common.BuilderInterface<A>;

  let { MAX_BITWIDTH; reverseCodeBits; restore_huffman_codes } = Common;

  public type DecoderOptions = {
    max_bitwidth : Nat;
  };

  public class Builder(max_bitwidth : Nat) : BuilderInterface<Decoder> {
    let table_size = (2 ** max_bitwidth);
    let table = Array.init<Nat>(table_size, MAX_BITWIDTH + 1);

    public func setMapping(symbol : Nat, code : Code) : Result<(), Text> {
      if (code.bitwidth > max_bitwidth) {
        return #err("Code bitwidth is greater than max bitwidth");
      };

      let value = (Nat16.fromNat(symbol) << 5) | Nat16.fromNat(code.bitwidth);

      let code_be = reverseCodeBits(code);

      let possible_mappings = (2 ** (max_bitwidth - code.bitwidth)) - 1 : Nat;

      for (p in Iter.range(0, possible_mappings)) {
        let padding = Nat16.fromNat(p);
        let i = Nat16.toNat((padding << Nat16.fromNat(code.bitwidth)) | code_be.bits);

        if (i >= table.size()) {
          return #err(
            "Index out of bounds at i = " # debug_show i
            # " | table size = " # debug_show table.size()
            # " | padding = " # debug_show padding
            # " | code_be.bits = " # debug_show (code_be.bits)
            # " | code_be.bitwidth = " # debug_show (code.bitwidth)
          );
        };

        if (table[i] != MAX_BITWIDTH + 1) {
          return #err("Bit region conflict");
        };

        table[i] := Nat16.toNat(value);
      };

      #ok();
    };

    public func build() : Decoder {
      Decoder(table, max_bitwidth);
    };
  };

  public func fromBitwidths(bitwidths : [Nat]) : Result<Decoder, Text> {
    let max_bitwidth = Array.foldRight<Nat, Nat>(bitwidths, 0, func(a, b) = Nat.max(a, b));
    let builder = Builder(max_bitwidth);

    restore_huffman_codes(builder, bitwidths);
  };

  public class Decoder(table : [var Nat], max_bitwidth : Nat) {

    var min_bidwidth : ?Nat = null;

    public func decode(reader : BitReader) : Result<Nat, Text> {

      var value = 0;
      var bitwidth = 0;
      var peek_bitwidth = Option.get(min_bidwidth, 1);

      label _loop loop {
        let code = reader.peekBits(peek_bitwidth);
        value := table[code];
        bitwidth := (value % (2 ** 5)); /* take last 5 bits */

        if (bitwidth <= peek_bitwidth) {
          break _loop;
        };

        if (bitwidth > max_bitwidth) {
          return #err("Invalid bitwidth " # debug_show bitwidth # " at position " # debug_show reader.getPosition() # " (max bitwidth is " # debug_show max_bitwidth # ") peeked: " # debug_show (peek_bitwidth) # " code: " # debug_show (code) # " value: " # debug_show (value) # " table size: " # debug_show (table.size()));
        };

        peek_bitwidth := bitwidth;
      };

      reader.skipBits(bitwidth);

      switch (min_bidwidth) {
        case (null) min_bidwidth := ?bitwidth;
        case (?n) min_bidwidth := ?Nat.min(n, bitwidth);
      };

      let decoded = value / (2 ** 5); /* == value >> 5 */
      #ok(decoded);
    };
  };
};
