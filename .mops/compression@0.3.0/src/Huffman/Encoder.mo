import Array "mo:base@0/Array";
import Nat16 "mo:base@0/Nat16";
import Nat "mo:base@0/Nat";
import Buffer "mo:base@0/Buffer";
import Result "mo:base@0/Result";
import Order "mo:base@0/Order";
import Heap "mo:base@0/Heap";

import BitBuffer "mo:bitbuffer@1/BitBuffer";
import Itertools "mo:itertools@0/Iter";
import RevIter "mo:itertools@0/RevIter";
import BitReader "../BitReader";

import Common "Common";
import Prelude "mo:base@0/Prelude";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  type Result<A, B> = Result.Result<A, B>;
  type BitBuffer = BitBuffer.BitBuffer;
  type BitReader = BitReader.BitReader;

  let { reverseCodeBits } = Common;

  public type Code = Common.Code;

  public func fromBitwidths(bitwidths : [Nat]) : Result<Encoder, Text> {
    if (bitwidths.size() == 0) return #err("bitwidths is empty");

    var symbol_count = bitwidths.size() : Nat;

    while (symbol_count > 0 and bitwidths[symbol_count - 1] == 0) {
      symbol_count -= 1;
    };

    let builder = Builder(symbol_count + 1);

    Common.restore_huffman_codes<Encoder>(builder, bitwidths);
  };

  public func fromFrequencies(frequencies : [Nat], bitwidth : Nat) : Result<Encoder, Text> {
    let max_bitwidth = Nat.min(
      bitwidth,
      HuffmanCodes.calc_max_bitwidth(frequencies),
    );

    let bitwidthes : [Nat] = HuffmanCodes.calc_bitwidths(max_bitwidth, frequencies);

    fromBitwidths(bitwidthes);
  };

  public class Builder(symbols_count : Nat) : Common.BuilderInterface<Encoder> {
    let table : [var Code] = Array.init(symbols_count, { bitwidth = 0; bits = 0 : Nat16 });

    public let setMapping = func(symbol : Nat, code : Code) : Result<(), Text> {
      let prev_code = table[symbol];
      assert prev_code.bitwidth == 0 and prev_code.bits == 0;

      if (prev_code.bitwidth != 0 or prev_code.bits != 0) {
        return #err("symbol has already been mapped");
      };

      table[symbol] := reverseCodeBits(code);

      #ok;
    };

    public func build() : Encoder {
      Encoder(table);
    };
  };

  public class Encoder(table : [var Code]) {

    public func encode(bitbuffer : BitBuffer, symbol : Nat) {
      let code = table[symbol];
      assert code != { bitwidth = 0; bits = 0 : Nat16 };
      bitbuffer.addBits(code.bitwidth, Nat16.toNat(code.bits));
    };

    public func lookup(symbol : Nat) : Code {
      assert symbol < table.size();
      table[symbol];
    };

    public func max_symbol() : Nat {
      var max_index = 0;

      let range = RevIter.range(0, table.size());

      label for_loop for (i in range.rev()) {

        if (table[i].bitwidth > 0) {
          max_index := i;
          break for_loop;
        };

      };

      max_index;
    };
  };

  type Tuple<A, B> = (A, B);

  type CompareFn<A> = (A, A) -> Order.Order;

  func tuple_compare<A, B>(cmp1 : CompareFn<A>, cmp2 : CompareFn<B>) : CompareFn<Tuple<A, B>> {
    func(a : Tuple<A, B>, b : Tuple<A, B>) : Order.Order {
      let (a1, a2) = a;
      let (b1, b2) = b;

      let res1 = cmp1(a1, b1);

      if (res1 == #equal) {
        return cmp2(a2, b2);
      } else {
        return res1;
      };
    };
  };

  module HuffmanCodes {
    public func calc_max_bitwidth(frequencies : [Nat]) : Nat {

      let cmp = tuple_compare(Nat.compare, Nat.compare);
      let heap = Heap.Heap<(Nat, Nat)>(cmp);
      var heap_size = 0;

      for (freq in frequencies.vals()) {
        if (freq > 0) {
          heap.put((freq, 0));
          heap_size += 1;
        };
      };

      while (heap_size > 1) {
        let ?(freq1, bitwidth1) = heap.removeMin() else Prelude.unreachable();
        let ?(freq2, bitwidth2) = heap.removeMin() else Prelude.unreachable();

        heap.put((freq1 + freq2, Nat.max(bitwidth1, bitwidth2) + 1));
        heap_size -= 1;
      };

      let max_bitwidth = switch (heap.removeMin()) {
        case (?(_, bitwidth)) bitwidth;
        case (_) 0;
      };

      Nat.max(max_bitwidth, 1);
    };

    public func calc_bitwidths(max_bitwidth : Nat, frequencies : [Nat]) : [Nat] {
      LengthLimited.calc_bitwidths(max_bitwidth, frequencies);
    };

    public module LengthLimited {

      type Node = {
        var weight : Nat;
        symbols : Buffer<Nat>;
      };

      public module Node {
        public func merge(self : Node, other : Node) {
          self.weight += other.weight;
          self.symbols.append(other.symbols);
        };
      };

      public func calc_bitwidths(max_bitwidth : Nat, frequencies : [Nat]) : [Nat] {
        let nodes = Buffer.Buffer<Node>(8);

        func deep_copy(nodes : Buffer.Buffer<Node>) : Buffer.Buffer<Node> {
          let new_nodes = Buffer.Buffer<Node>(nodes.size());

          for (node in nodes.vals()) {
            let new_node = {
              var weight = node.weight;
              symbols = Buffer.clone(node.symbols);
            };

            new_nodes.add(new_node);
          };

          new_nodes;
        };

        for ((symbol, weight) in Itertools.enumerate(frequencies.vals())) {
          if (weight > 0) {
            let node = {
              var weight = weight;
              symbols = Buffer.fromArray<Nat>([symbol]);
            };

            nodes.add(node);
          };
        };

        let cmp = func(a : Node, b : Node) : Order.Order {
          Nat.compare(a.weight, b.weight);
        };

        nodes.sort(cmp);

        var weighted_nodes = deep_copy(nodes);

        for (_ in Itertools.range(0, max_bitwidth - 1)) {
          package(weighted_nodes);
          weighted_nodes := merge(weighted_nodes, deep_copy(nodes));
        };

        package(weighted_nodes);

        let code_bitwidths = Array.init<Nat>(frequencies.size(), 0);
        let unique_bitwidth_symbols = Buffer.Buffer<Nat>(8);

        for (node in weighted_nodes.vals()) {
          for (symbol in node.symbols.vals()) {
            code_bitwidths[symbol] += 1;
            if (code_bitwidths[symbol] == 1) {
              unique_bitwidth_symbols.add(symbol);
            };
          };
        };

        Array.freeze(code_bitwidths);
      };

      public func merge(buffer_a : Buffer<Node>, buffer_b : Buffer<Node>) : Buffer<Node> {
        var i = 0;
        var j = 0;

        let buffer = Buffer.Buffer<Node>(buffer_a.size() + buffer_b.size());

        while (i < buffer_a.size() and j < buffer_b.size()) {
          let a = buffer_a.get(i);
          let b = buffer_b.get(j);

          if (a.weight < b.weight) {
            i += 1;
            buffer.add(a);
          } else {
            j += 1;
            buffer.add(b);
          };
        };

        if (i < buffer_a.size()) {
          for (i in Itertools.range(i, buffer_a.size())) {
            buffer.add(buffer_a.get(i));
          };
        } else {
          for (j in Itertools.range(j, buffer_b.size())) {
            buffer.add(buffer_b.get(j));
          };
        };

        buffer;
      };

      public func package(nodes : Buffer<Node>) {

        if (nodes.size() < 2) return;

        let new_size = (nodes.size()) / 2;

        var i = 0;

        while (i < new_size) {
          let j = i * 2 + 1;

          if (j < nodes.size()) {
            let a = nodes.get(i * 2);
            let b = nodes.get(j);

            Node.merge(a, b);
          };

          nodes.put(i, nodes.get(i * 2));

          i += 1;
        };

        while (nodes.size() > new_size) {
          ignore nodes.removeLast();
        };

      };
    };
  };
};
