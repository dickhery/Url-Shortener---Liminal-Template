import Iter "mo:base@0/Iter";
import Buffer "mo:base@0/Buffer";
import Debug "mo:base@0/Debug";

import It "mo:itertools@0/Iter";

import Common "Common";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  type LzssEntry = Common.LzssEntry;

  public func decode(lzss_buffer : Buffer<LzssEntry>) : Buffer<Nat8> {
    let buffer = Buffer.Buffer<Nat8>(8);

    for (entry in lzss_buffer.vals()) {
      switch (entry) {
        case (#literal(byte)) {
          buffer.add(byte);
        };
        case (#pointer((backward_offset, len))) {
          if (backward_offset > buffer.size()) {
            Debug.trap("LZSS decode(): Invalid LZSS #pointer (backward_offset > decompressed data size)");
          };

          let index = ((buffer.size() - backward_offset) : Nat) : Nat;

          for (i in It.range(index, index + len)) {
            if (i >= buffer.size()) {
              let rle_index = index + (i % buffer.size());
              buffer.add(buffer.get(rle_index));
            } else {
              buffer.add(buffer.get(i));
            };
          };
        };
      };
    };

    buffer;
  };

  public class Decoder() {

    public func decodeEntry(output_buffer : Buffer<Nat8>, entry : LzssEntry) {
      switch (entry) {
        case (#literal(byte)) {
          output_buffer.add(byte);
        };
        case (#pointer((backward_offset, len))) {
          if (backward_offset > output_buffer.size()) {
            Debug.trap("LZSS decode(): Invalid LZSS #pointer (backward_offset > decompressed data size)");
          };

          let index = ((output_buffer.size() - backward_offset) : Nat) : Nat;

          for (i in It.range(index, index + len)) {
            if (i >= output_buffer.size()) {
              let rle_index = index + (i % output_buffer.size());
              output_buffer.add(output_buffer.get(rle_index));
            } else {
              output_buffer.add(output_buffer.get(i));
            };
          };
        };
      };
    };

    public func decodeIter(output_buffer : Buffer<Nat8>, lzss_iter : Iter.Iter<LzssEntry>) {
      for (entry in lzss_iter) {
        decodeEntry(output_buffer, entry);
      };
    };

    public func decode(output_buffer : Buffer<Nat8>, lzss_buffer : Buffer<LzssEntry>) {
      for (entry in lzss_buffer.vals()) {
        decodeEntry(output_buffer, entry);
      };
    };
  };
};
