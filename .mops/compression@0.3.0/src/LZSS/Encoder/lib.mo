import Blob "mo:base@0/Blob";
import Buffer "mo:base@0/Buffer";
import Deque "mo:base@0/Deque";
import Iter "mo:base@0/Iter";
import Option "mo:base@0/Option";
import Nat "mo:base@0/Nat";
import Nat8 "mo:base@0/Nat8";
import Result "mo:base@0/Result";
import Prelude "mo:base@0/Prelude";

import It "mo:itertools@0/Iter";
import CircularBuffer "mo:circular-buffer@0";
import BufferDeque "mo:buffer-deque@0/BufferDeque";

import Common "../Common";

import PrefixTable "PrefixTable";

module {
  type Buffer<A> = Buffer.Buffer<A>;
  type CircularBuffer<A> = CircularBuffer.CircularBuffer<A>;
  type Deque<A> = Deque.Deque<A>;
  type Iter<A> = Iter.Iter<A>;

  type LzssEntry = Common.LzssEntry;
  type Result<Ok, Err> = Result.Result<Ok, Err>;

  public type Sink = {
    add : (entry : LzssEntry) -> ();
  };

  public func Default() : Encoder {
    Encoder(null);
  };

  public func encode(bytes : [Nat8]) : Buffer<LzssEntry> {
    let lzss = Default();
    let buffer = Buffer.Buffer<LzssEntry>(8);

    lzss.encode(bytes, buffer);
    lzss.flush(buffer);
    buffer;
  };

  public class Encoder(opt_window_size : ?Nat) {

    let window_size = Option.get(opt_window_size, Common.MATCH_WINDOW_SIZE);
    let search_buffer = CircularBuffer.CircularBuffer<Nat8>(window_size);

    let prefix_table = PrefixTable.PrefixTable();

    var input_size : Nat = 0;

    public func size() : Nat = input_size;
    public func windowSize() : Nat = window_size;

    public func encodeBlob(blob : Blob, sink : Sink) {
      let bytes = Blob.toArray(blob);
      encode(bytes, sink);
    };

    let byte_buffer = BufferDeque.BufferDeque<Nat8>(3);
    let cache_buffer = CircularBuffer.CircularBuffer<Nat8>(2);
    var match_index : ?Nat = null;

    func encode_as_literals(n : Nat, sink : Sink) {
      for (i in It.range(0, n)) {
        let ?byte = byte_buffer.popFront() else Prelude.unreachable();
        search_buffer.push(byte);
        sink.add(#literal(byte));
        input_size += 1;
      };
    };

    public func encode_byte(future_byte : Nat8, sink : Sink) {

      byte_buffer.addBack(future_byte);

      if (cache_buffer.size() == 2) {
        ignore prefix_table.insert(
          [cache_buffer.get(0), cache_buffer.get(1), byte_buffer.get(0)],
          0,
          3,
          input_size - 2,
        );

        ignore cache_buffer.removeFirst();
      } else if (cache_buffer.size() == 1 and byte_buffer.size() >= 2) {
        ignore prefix_table.insert(
          [cache_buffer.get(0), byte_buffer.get(0), byte_buffer.get(1)],
          0,
          3,
          input_size - 1,
        );

        ignore cache_buffer.removeFirst();
      };

      if (byte_buffer.size() < 3) return;

      if (byte_buffer.size() == 3) {
        let opt_prefix_index = prefix_table.insert(
          [
            byte_buffer.get(0),
            byte_buffer.get(1),
            byte_buffer.get(2),
          ],
          0,
          3,
          input_size,
        );

        switch (opt_prefix_index) {
          case (null) {
            encode_as_literals(1, sink);
            match_index := null;
          };
          case (?prefix_index) {
            let backward_offset = (input_size - prefix_index) : Nat;
            if (backward_offset > search_buffer.size()) {
              encode_as_literals(1, sink);
              match_index := null;
            } else {
              match_index := opt_prefix_index;
            };
          };
        };
      } else {
        let ?prefix_index = match_index else Prelude.unreachable();
        let backward_offset = (input_size - prefix_index) : Nat;

        let start_index = (search_buffer.size() - backward_offset) : Nat;
        let future_byte_index = start_index + (byte_buffer.size() - 1) : Nat;

        if (future_byte_index >= search_buffer.size() or future_byte != search_buffer.get(future_byte_index) or byte_buffer.size() >= Common.MATCH_MAX_SIZE) {
          let len = (byte_buffer.size() - 1) : Nat;

          for (i in It.range(0, len)) {
            if (byte_buffer.size() >= 3) {
              let index = i + input_size;

              ignore prefix_table.insert(
                [byte_buffer.get(0), byte_buffer.get(1), byte_buffer.get(2)],
                0,
                3,
                index,
              );
            };

            let ?byte = byte_buffer.popFront() else Prelude.unreachable();
            search_buffer.push(byte);

            if (byte_buffer.size() < 3) {
              cache_buffer.add(byte);
            };
          };

          sink.add(#pointer(backward_offset, len));
          input_size += len;
          match_index := null;
        };
      };
    };

    public func encode(bytes : [Nat8], sink : Sink) {
      for (byte in bytes.vals()) {
        encode_byte(byte, sink);
      };
    };

    public func flush(sink : Sink) {
      let len = byte_buffer.size();
      if (len == 0) return;

      if (Option.isSome(match_index) and len >= 3) {
        let ?prefix_index = match_index else Prelude.unreachable();
        let backward_offset = (input_size - prefix_index) : Nat;
        sink.add(#pointer(backward_offset, len));
      } else {
        for (i in It.range(0, len)) {
          let ?byte = byte_buffer.popFront() else Prelude.unreachable();
          sink.add(#literal(byte));
        };
      };

    };

    public func finish(sink : Sink) {
      flush(sink);
      clear();
    };

    public func clear() {
      search_buffer.clear();
      prefix_table.clear();
      byte_buffer.clear();
      input_size := 0;
      match_index := null;
    };

    public func encode_v1(bytes : [Nat8], sink : Sink) {
      var curr_index = 0;

      label while_loop while (curr_index < bytes.size()) {

        if (((bytes.size() - curr_index) : Nat) >= 3) {
          let opt_prefix_index = prefix_table.insert(bytes, curr_index, 3, input_size);

          switch (opt_prefix_index) {
            case (?prefix_index) {
              let backward_offset = (input_size - prefix_index) : Nat;

              if (backward_offset <= window_size) {
                let search_index = (search_buffer.size() - backward_offset) : Nat;

                let len = longest_prefix_length(bytes, search_index, curr_index);

                label for_loop for (i in It.range(0, len)) {
                  if ((bytes.size() - (curr_index + i) : Nat) < 3) {
                    break for_loop;
                  };
                  ignore prefix_table.insert(bytes, curr_index + i, 3, input_size + i);
                  search_buffer.push(bytes[curr_index + i]);
                };

                sink.add(#pointer(backward_offset, len));

                curr_index += len;
                input_size += len;

                continue while_loop;
              };
            };
            case (null) {};
          };
        };

        search_buffer.push(bytes[curr_index]);
        input_size += 1;

        sink.add(#literal(bytes[curr_index]));
        curr_index += 1;
      };
    };

    func longest_prefix_length(
      bytes : [Nat8],
      _search_index : Nat,
      _curr_index : Nat,
    ) : Nat {
      var len = 3;

      func is_match() : Bool {
        let search_index = _search_index + len;
        let curr_index = _curr_index + len;

        if (search_index >= search_buffer.size() or curr_index >= bytes.size()) {
          return false;
        };

        search_buffer.get(search_index) == bytes[curr_index];
      };

      while (is_match()) {
        len += 1;
      };

      len;
    };
  };
};
