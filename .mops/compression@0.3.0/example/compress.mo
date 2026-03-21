import Blob "mo:base@0/Blob";
import Nat "mo:base@0/Nat";
import Array "mo:base@0/Array";
import Buffer "mo:base@0/Buffer";
import Random "mo:base@0/Random";
import Result "mo:base@0/Result";
import GzipEncoder "../src/Gzip/Encoder";
import GzipDecoder "../src/Gzip/Decoder";

import Itertools "mo:itertools@0/Iter";
import Principal "mo:base@0/Principal";

shared ({ caller = owner }) actor class User() = self {

  type Buffer<A> = Buffer.Buffer<A>;
  type Result<A, B> = Result.Result<A, B>;

  stable var _data : ?[Nat8] = null;
  stable var _compressed : ?GzipEncoder.EncodedResponse = null;
  let MB = 1024 * 1024;

  public func generate_data() : async () {
    let seed : Blob = await Random.blob();
    let finite = Random.Finite(seed);

    _data := ?(
      Array.tabulate<Nat8>(
        10 * MB,
        func(i : Nat) : Nat8 {
          let ?byte = finite.byte() else return Random.byteFrom(seed);
          byte;
        },
      )
    );
  };

  func get_data() : [Nat8] {
    switch (_data) {
      case (?d) return d;
      case (_) return [];
    };
  };

  let block_size = 1 * MB;
  let gzip_encoder = GzipEncoder.EncoderBuilder().blockSize(block_size).build();

  func canisterId() : Principal {
    Principal.fromActor(self);
  };

  public shared ({ caller }) func compress(chunk : [Nat8]) : async () {
    assert caller == canisterId();

    gzip_encoder.encode(chunk);
  };

  public func compress_all() : async () {
    let data = get_data();
    let chunks_iter = Itertools.chunks(data.vals(), block_size);

    for (chunk in chunks_iter) {
      await compress(chunk);
    };

    _compressed := ?gzip_encoder.finish(); // returns the encoded response and resets the encoder
  };

  let gzip_decoder = GzipDecoder.Decoder();

  public shared ({ caller }) func decode(chunk : [Nat8]) : async () {
    assert caller == canisterId();
    gzip_decoder.decode(chunk);
  };

  public func decode_data() : async Bool {
    let ?compressed = _compressed else return false;

    for (chunk in compressed.chunks.vals()) {
      await decode(chunk);
    };

    let res = gzip_decoder.finish(); // returns the decoded response and resets the decoder
    Buffer.toArray(res.buffer) == get_data();
  };
};
