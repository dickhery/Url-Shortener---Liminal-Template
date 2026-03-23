import Array "mo:base@0/Array";
import Buffer "mo:base@0/Buffer";
import Debug "mo:base@0/Debug";
import Nat8 "mo:base@0/Nat8";
import Nat16 "mo:base@0/Nat16";
import Iter "mo:base@0/Iter";
import Nat "mo:base@0/Nat";
import Result "mo:base@0/Result";

import BitBuffer "mo:bitbuffer@1/BitBuffer";
import Itertools "mo:itertools@0/Iter";
import RevIter "mo:itertools@0/RevIter";

import Common "../LZSS/Common";
import Utils "../utils";
import HuffmanEncoder "../Huffman/Encoder";
import HuffmanDecoder "../Huffman/Decoder";
import BitReader "../BitReader";

import { buffer_get_last; send_err } "../utils";

module {
  type BitBuffer = BitBuffer.BitBuffer;
  type BitReader = BitReader.BitReader;
  type Iter<A> = Iter.Iter<A>;

  type Buffer<A> = Buffer.Buffer<A>;
  type Result<A, B> = Result.Result<A, B>;

  public type Symbol = Common.LzssEntry or {
    #EndOfBlock;
  };

  let FIXED_LENGTH_CODES : [{
    bitwidth : Nat;
    symbol_start : Nat;
    symbol_end : Nat;
    base_code : Nat16;
  }] = [
    {
      bitwidth = 8;
      symbol_start = 0;
      symbol_end = 143;
      base_code = 0x30;
    },
    {
      bitwidth = 9;
      symbol_start = 144;
      symbol_end = 255;
      base_code = 0x190;
    },
    {
      bitwidth = 7;
      symbol_start = 256;
      symbol_end = 279;
      base_code = 0x00;
    },
    {
      bitwidth = 8;
      symbol_start = 280;
      symbol_end = 287;
      base_code = 0xc0;
    },
  ];

  let BITWIDTH_CODE_ORDER : [Nat] = [
    16,
    17,
    18,
    0,
    8,
    7,
    9,
    6,
    10,
    5,
    11,
    4,
    12,
    3,
    13,
    2,
    14,
    1,
    15,
  ];

  /// Encodes the literal and length Deflate Symbol to Nat16 and returns the extra bits
  public func lengthCode(symbol : Symbol) : (Nat16, Nat, Nat16) {
    switch symbol {
      case (#EndOfBlock) { (256, 0, 0) };

      case (#literal(byte)) { (Utils.nat8_to_16(byte), 0, 0) };

      case (#pointer(_, length)) {
        if (length > 258 or length < 3) {
          Debug.trap("Invalid deflate distance pair: length '" # debug_show (length) # "' is out of range 3 <= length <= 258");
        };

        let len16 = Nat16.fromNat(length);

        var marker = 0 : Nat16;
        var extra_bits = 0;
        var offset = 0 : Nat16;

        if (len16 <= 10) {
          marker := 257 + (len16 - 3);
        } else if (len16 <= 18) {
          marker := 265 + ((len16 - 11) / 2);
          extra_bits := 1;
          offset := (len16 - 11) % 2;
        } else if (len16 <= 34) {
          marker := 269 + ((len16 - 19) / 4);
          extra_bits := 2;
          offset := (len16 - 19) % 4;
        } else if (len16 <= 66) {
          marker := 273 + ((len16 - 35) / 8);
          extra_bits := 3;
          offset := (len16 - 35) % 8;
        } else if (len16 <= 130) {
          marker := 277 + ((len16 - 67) / 16);
          extra_bits := 4;
          offset := (len16 - 67) % 16;
        } else if (len16 <= 257) {
          marker := 281 + ((len16 - 131) / 32);
          extra_bits := 5;
          offset := (len16 - 131) % 32;
        } else {
          marker := 285;
        };

        (marker, extra_bits, offset);
      };
    };
  };

  public let MAX_DISTANCE = 32768;
  public func distanceCode(symbol : Symbol) : ?(Nat, Nat, Nat16) {
    switch (symbol) {
      case (#pointer(distance, _)) {
        if (distance > MAX_DISTANCE or distance == 0) {
          Debug.trap("Invalid deflate distance pair: distance '" # debug_show (distance) # "' is out of range 1 <= distance <= 32768");
        };

        if (distance >= 1 and distance <= 4) {
          ?(distance - 1, 0, 0);
        } else {
          var extra_bits = 1;
          var base = 4;
          var marker = 4;

          while (base * 2 < distance) {
            extra_bits += 1;
            marker += 2;
            base *= 2;
          };

          let half = base / 2;
          let delta = (distance - base - 1) : Nat;

          let offset = Nat16.fromNat(delta % half);
          if (distance <= base + half) {
            ?(marker, extra_bits, offset);
          } else {
            ?(marker + 1, extra_bits, offset);
          };
        };
      };
      case (_) null;
    };
  };

  public class Encoder(literal_encoder : HuffmanEncoder.Encoder, distance_encoder : HuffmanEncoder.Encoder) {

    public let literal = literal_encoder;
    public let distance = distance_encoder;

    public func encode(bitbuffer : BitBuffer, symbol : Symbol) {

      let (marker, extra_bits, offset) = lengthCode(symbol);
      literal_encoder.encode(bitbuffer, Nat16.toNat(marker));

      if (extra_bits > 0) {
        bitbuffer.addBits(extra_bits, Nat16.toNat(offset));
      };

      switch (distanceCode(symbol)) {
        case (?(marker, extra_bits, offset)) {
          distance_encoder.encode(bitbuffer, marker);
          if (extra_bits > 0) {
            bitbuffer.addBits(extra_bits, Nat16.toNat(offset));
          };
        };
        case (null) {};
      };
    };
  };

  let LENGTH_TABLE : [(Nat, Nat)] = [
    (3, 0),
    (4, 0),
    (5, 0),
    (6, 0),
    (7, 0),
    (8, 0),
    (9, 0),
    (10, 0),
    (11, 1),
    (13, 1),
    (15, 1),
    (17, 1),
    (19, 2),
    (23, 2),
    (27, 2),
    (31, 2),
    (35, 3),
    (43, 3),
    (51, 3),
    (59, 3),
    (67, 4),
    (83, 4),
    (99, 4),
    (115, 4),
    (131, 5),
    (163, 5),
    (195, 5),
    (227, 5),
    (258, 0),
  ];

  let DISTANCE_TABLE : [(Nat, Nat)] = [
    (1, 0),
    (2, 0),
    (3, 0),
    (4, 0),
    (5, 1),
    (7, 1),
    (9, 2),
    (13, 2),
    (17, 3),
    (25, 3),
    (33, 4),
    (49, 4),
    (65, 5),
    (97, 5),
    (129, 6),
    (193, 6),
    (257, 7),
    (385, 7),
    (513, 8),
    (769, 8),
    (1025, 9),
    (1537, 9),
    (2049, 10),
    (3073, 10),
    (4097, 11),
    (6145, 11),
    (8193, 12),
    (12_289, 12),
    (16_385, 13),
    (24_577, 13),
  ];

  public class Decoder(literal_decoder : HuffmanDecoder.Decoder, distance_decoder : HuffmanDecoder.Decoder) {
    public func decode(reader : BitReader) : Result<Symbol, Text> {
      let symbol_res = decode_literal(reader);

      let #ok(symbol) = symbol_res else return symbol_res;

      let #pointer(_, length) = symbol else return #ok(symbol);

      let bwd_res = decode_distance(reader);

      let backward_distance = switch (bwd_res) {
        case (#ok(backward_distance)) backward_distance;
        case (#err(msg)) return #err(msg);
      };

      let back_ref = #pointer(backward_distance, length);

      #ok(back_ref);
    };

    func decode_literal(reader : BitReader) : Result<Symbol, Text> {
      let res = literal_decoder.decode(reader);

      let val = switch (res) {
        case (#ok(val)) val;
        case (#err(msg)) return #err(msg);
      };

      let symbol = if (val >= 0 and val <= 255) {
        #literal(Nat8.fromNat(val));
      } else if (val == 256) {
        #EndOfBlock;
      } else if (val == 286 or val == 287) {
        return #err(
          "Invalid deflate symbol " # debug_show (val) # ". Values 286 and 287 should not be in the compressed bytes."
        );
      } else {
        let (base, extra_bits) = LENGTH_TABLE[val - 257];
        let extra = reader.readBits(extra_bits);

        #pointer(0, base + extra);
      };

      #ok(symbol);
    };

    func decode_distance(reader : BitReader) : Result<Nat, Text> {
      let res = distance_decoder.decode(reader);

      let val = switch (res) {
        case (#ok(val)) val;
        case (#err(msg)) return #err(msg);
      };

      let (base, extra_bits) = DISTANCE_TABLE[val];
      let distance = base + reader.readBits(extra_bits);

      #ok(distance);
    };
  };

  public type HuffmanCodec = {
    build : (Iter<Symbol>) -> Result<Encoder, Text>;
    save : (BitBuffer, Encoder) -> Result<(), Text>;
    load : (BitReader) -> Result<Decoder, Text>;
  };

  public class FixedHuffmanCodec() : HuffmanCodec {

    public func build(_ : Iter<Symbol>) : Result<Encoder, Text> {
      let literal_builder = HuffmanEncoder.Builder(288);

      for (
        {
          bitwidth;
          symbol_start;
          symbol_end;
          base_code;
        } in FIXED_LENGTH_CODES.vals()
      ) {

        for (symbol in Iter.range(symbol_start, symbol_end)) {
          let code = {
            bitwidth;
            bits = base_code + Nat16.fromNat(symbol - symbol_start);
          };

          switch (literal_builder.setMapping(symbol, code)) {
            case (#ok(_)) {};
            case (#err(msg)) return #err(if (msg.size() > 0) msg else "Failed to set mapping for symbol ");
          };
        };

      };

      let literal_encoder = literal_builder.build();

      let distance_builder = HuffmanEncoder.Builder(30);

      for (symbol in Iter.range(0, 29)) {
        let code = { bitwidth = 5; bits = Nat16.fromNat(symbol) };

        switch (distance_builder.setMapping(symbol, code)) {
          case (#ok(_)) {};
          case (#err(msg)) return #err(if (msg.size() > 0) msg else "Failed to set mapping for symbol ");
        };
      };

      let distance_encoder = distance_builder.build();

      #ok(Encoder(literal_encoder, distance_encoder));
    };

    public func save(_ : BitBuffer, _ : Encoder) : Result<(), Text> = #ok();

    public func load(_ : BitReader) : Result<Decoder, Text> {
      let literal_decoder = HuffmanDecoder.Builder(9);

      for (
        {
          bitwidth;
          symbol_start;
          symbol_end;
          base_code;
        } in FIXED_LENGTH_CODES.vals()
      ) {
        for (symbol in Iter.range(symbol_start, symbol_end)) {
          let code = {
            bitwidth;
            bits = base_code + Nat16.fromNat(symbol - symbol_start);
          };

          let res = literal_decoder.setMapping(symbol, code);
          switch (res) {
            case (#ok(_)) ();
            case (#err(msg)) return #err(msg);
          };
        };
      };

      let distance_decoder = HuffmanDecoder.Builder(5);

      for (symbol in Iter.range(0, 29)) {
        let code = { bitwidth = 5; bits = Nat16.fromNat(symbol) };

        let res = distance_decoder.setMapping(symbol, code);
        switch (res) {
          case (#ok(_)) ();
          case (#err(msg)) return #err(msg);
        };
      };

      let symbol_decoder = Decoder(literal_decoder.build(), distance_decoder.build());
      #ok(symbol_decoder);
    };
  };

  public class DynamicHuffmanCodec() : HuffmanCodec {
    public func build(symbols_iter : Iter<Symbol>) : Result<Encoder, Text> {
      let literal_freq = Array.init<Nat>(286, 0);
      let distance_freq = Array.init<Nat>(30, 0);

      var empty_distance_table = true;

      for (symbol in symbols_iter) {
        let (marker, _, _) = lengthCode(symbol);
        literal_freq[Nat16.toNat(marker)] += 1;

        ignore do ? {
          let (marker, _, _) = distanceCode(symbol)!;
          distance_freq[marker] += 1;
          empty_distance_table := false;
        };
      };

      if (empty_distance_table) {
        distance_freq[0] := 1;
      };

      let literal_result = HuffmanEncoder.fromFrequencies(Array.freeze(literal_freq), 15);
      let literal_encoder = switch (literal_result) {
        case (#ok(encoder)) encoder;
        case (#err(err)) return #err(err);
      };

      let distance_result = HuffmanEncoder.fromFrequencies(Array.freeze(distance_freq), 15);
      let distance_encoder = switch (distance_result) {
        case (#ok(encoder)) encoder;
        case (#err(err)) return #err(err);
      };

      #ok(Encoder(literal_encoder, distance_encoder));
    };

    public func save(bitbuffer : BitBuffer, codec : Encoder) : Result<(), Text> {
      let literal_code_count = Nat.max(257, codec.literal.max_symbol() + 1);
      let distance_code_count = Nat.max(1, codec.distance.max_symbol() + 1);

      let codes = build_bitwidth_codes(codec, literal_code_count, distance_code_count);

      let code_counts = Array.init<Nat>(19, 0);

      for (bit_code in codes.vals()) {
        code_counts[bit_code.symbol] += 1;
      };

      let #ok(bitwidth_encoder) = HuffmanEncoder.fromFrequencies(
        Array.freeze(code_counts),
        7,
      ) else return #err("Failed to build bitwidth encoder");

      let iter = RevIter.range(0, BITWIDTH_CODE_ORDER.size()).rev();

      var bitwidth_code_order_max = 0;
      label for_loop for (i in iter) {
        let index = BITWIDTH_CODE_ORDER[i];
        if (code_counts[index] > 0 and bitwidth_encoder.lookup(index).bitwidth > 0) {
          bitwidth_code_order_max := i;
          break for_loop;
        };
      };

      let bitwidth_code_count = Nat.max(4, bitwidth_code_order_max + 1);

      bitbuffer.addBits(5, literal_code_count - 257);
      bitbuffer.addBits(5, distance_code_count - 1);
      bitbuffer.addBits(4, bitwidth_code_count - 4);

      let code_order_iter = Itertools.take(
        BITWIDTH_CODE_ORDER.vals(),
        bitwidth_code_count,
      );

      for (i in code_order_iter) {
        var bitwidth = 0;
        if (code_counts[i] != 0) {
          bitwidth := bitwidth_encoder.lookup(i).bitwidth;
        };

        bitbuffer.addBits(3, bitwidth);
      };

      for ({ symbol; bitwidth; count } in codes.vals()) {
        bitwidth_encoder.encode(bitbuffer, symbol);

        if (bitwidth > 0) {
          bitbuffer.addBits(bitwidth, count);
        };
      };

      #ok();
    };

    type BitwidthCode = {
      symbol : Nat;
      count : Nat;
      bitwidth : Nat;
    };

    func build_bitwidth_codes(
      codec : Encoder,
      literal_code_count : Nat,
      distance_code_count : Nat,
    ) : Buffer.Buffer<BitwidthCode> {

      type RunLength = {
        value : Nat;
        var count : Nat;
      };

      func rle(
        buffer : Buffer<RunLength>,
        huffman_encoder : HuffmanEncoder.Encoder,
        code_count : Nat,
      ) {

        for (symbol in Itertools.range(0, code_count)) {
          let bitwidth = huffman_encoder.lookup(symbol).bitwidth;

          let has_same_value = switch (buffer_get_last(buffer)) {
            case (?elem) elem.value == bitwidth;
            case (_) false;
          };

          if (has_same_value) {
            Buffer.last(buffer).count += 1;
          } else {
            let elem = {
              value = bitwidth;
              var count = 1;
            };

            buffer.add(elem);
          };
        };
      };

      let run_len_buffer = Buffer.Buffer<RunLength>(8);
      rle(run_len_buffer, codec.literal, literal_code_count);
      rle(run_len_buffer, codec.distance, distance_code_count);

      let codes = Buffer.Buffer<BitwidthCode>(8);
      let bit_code = {
        symbol = 0;
        count = 0;
        bitwidth = 0;
      };

      for (elem in run_len_buffer.vals()) {
        if (elem.value != 0) {
          codes.add({ bit_code with symbol = elem.value });

          elem.count -= 1;

          while (elem.count >= 3) {
            let n = Nat.min(6, elem.count);
            codes.add({
              symbol = 16;
              count = n - 3;
              bitwidth = 2;
            });

            elem.count -= n;
          };

          for (_ in Itertools.range(0, elem.count)) {
            codes.add({ bit_code with symbol = elem.value });
          };
        } else {
          while (elem.count >= 11) {
            let n = Nat.min(138, elem.count);
            codes.add({
              symbol = 18;
              count = n - 11;
              bitwidth = 7;
            });

            elem.count -= n;
          };

          if (elem.count >= 3) {
            codes.add({
              symbol = 17;
              count = elem.count - 3;
              bitwidth = 3;
            });
          } else {
            for (_ in Itertools.range(0, elem.count)) {
              codes.add(bit_code);
            };
          };
        };
      };

      codes;
    };

    let MAX_DISTANCE_CODE_COUNT = 30;

    func loadBitwidths(reader : BitReader, bitwidths : Buffer<Nat>, code : Nat, last_opt : ?Nat) : Result<(), Text> {
      let (item, cnt) = switch (code) {
        case (16) {
          let cnt = reader.readBits(2) + 3;

          let last = switch (last_opt) {
            case (null) return #err("Invalid data: No previous value to count");
            case (?last_item) last_item;
          };

          (last, cnt);
        };
        case (17) {
          let zeroes = reader.readBits(3) + 3;
          (0, zeroes);
        };
        case (18) {
          let zeroes = reader.readBits(7) + 11;
          (0, zeroes);
        };
        case (_) {
          if (code >= 0 and code <= 15) {
            (code, 1);
          } else { return #err("Invalid code: " # debug_show (code)) };
        };
      };

      for (_ in Iter.range(1, cnt)) {
        bitwidths.add(item);
      };

      #ok();
    };

    public func load(reader : BitReader) : Result<Decoder, Text> {
      let literal_code_count = reader.readBits(5) + 257; // HLIT
      let distance_code_count = reader.readBits(5) + 1; // HDIST
      let bitwidth_code_count = reader.readBits(4) + 4; // HCLEN

      if (distance_code_count > MAX_DISTANCE_CODE_COUNT) {
        return #err("The value of HDIST is too big: max=" # debug_show (MAX_DISTANCE_CODE_COUNT) # ", actual=" # debug_show (distance_code_count));
      };

      let _bitwidths = Array.init<Nat>(19, 0);

      for (i in Iter.range(1, bitwidth_code_count)) {
        let index = BITWIDTH_CODE_ORDER[i - 1];
        _bitwidths[index] := reader.readBits(3);
      };

      let bitwidths = Array.freeze(_bitwidths);

      let bitwidth_decoder = switch (HuffmanDecoder.fromBitwidths(bitwidths)) {
        case (#ok(decoder)) decoder;
        case (#err(msg)) return #err(msg);
      };

      let bitwidths_buffer = Buffer.Buffer<Nat>(literal_code_count);

      while (bitwidths_buffer.size() < literal_code_count) {
        let code_res = bitwidth_decoder.decode(reader);
        let #ok(code) = code_res else return send_err(code_res);

        let last = buffer_get_last(bitwidths_buffer);
        let res = loadBitwidths(reader, bitwidths_buffer, code, last);

        switch (res) {
          case (#ok(_)) {};
          case (#err(msg)) return #err(msg);
        };
      };

      let (literal_bitwidths, distance_bitwidths) = Buffer.split(bitwidths_buffer, literal_code_count);

      while (distance_bitwidths.size() < distance_code_count) {

        let code = switch (bitwidth_decoder.decode(reader)) {
          case (#ok(code)) code;
          case (#err(msg)) return #err(msg);
        };

        let last = switch (buffer_get_last(distance_bitwidths)) {
          case (null) literal_bitwidths.getOpt(literal_bitwidths.size() - 1);
          case (item) item;
        };

        switch (loadBitwidths(reader, distance_bitwidths, code, last)) {
          case (#ok(_)) {};
          case (#err(msg)) return #err(msg);
        };
      };

      if (distance_bitwidths.size() > distance_code_count) {
        return #err("The distance code bitwidths are too large: expected=" # debug_show (distance_code_count) # ", actual=" # debug_show (distance_bitwidths.size()));
      };

      let literal_bitwidths_arr = Buffer.toArray(literal_bitwidths);
      let literal_decoder_res = HuffmanDecoder.fromBitwidths(literal_bitwidths_arr);
      let #ok(literal_decoder) = literal_decoder_res else return send_err(literal_decoder_res);

      let distance_bitwidths_arr = Buffer.toArray(distance_bitwidths);
      let distance_decoder_res = HuffmanDecoder.fromBitwidths(distance_bitwidths_arr);
      let #ok(distance_decoder) = distance_decoder_res else return send_err(distance_decoder_res);

      #ok(Decoder(literal_decoder, distance_decoder))

    };
  };
};
