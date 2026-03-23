import Buffer "mo:base@0/Buffer";
import TrieMap "mo:base@0/TrieMap";
import Text "mo:base@0/Text";
import Principal "mo:base@0/Principal";

import Gzip "../src/Gzip"; // "mo:deflate/Gzip"

import Itertools "mo:itertools@0/Iter";

shared ({ caller = owner }) actor class User() = self {
  let gzip_encoder = Gzip.EncoderBuilder().build();
  let gzip_decoder = Gzip.Decoder();

  let map = TrieMap.TrieMap<Text, Gzip.EncodedResponse>(Text.equal, Text.hash);

  func canister_id() : Principal { Principal.fromActor(self) };

  public shared ({ caller }) func compress(chunk : [Nat8]) : async () {
    assert caller == canister_id();

    gzip_encoder.encode(chunk);
  };

  public shared ({ caller }) func decode(chunk : [Nat8]) : async () {
    assert caller == canister_id();
    gzip_decoder.decode(chunk);
  };

  func compress_data(data : [Nat8]) : async* Gzip.EncodedResponse {
    let chunks_iter = Itertools.chunks(data.vals(), gzip_encoder.block_size());

    for (chunk in chunks_iter) {
      await compress(chunk);
    };

    // returns the encoded response and resets the encoder
    let compressed = gzip_encoder.finish();

    return compressed;
  };

  func decode_data(compressed : Gzip.EncodedResponse) : async* [Nat8] {

    for (chunk in compressed.chunks.vals()) {
      await decode(chunk);
    };

    // returns the decoded response and resets the decoder
    let decoded_response = gzip_decoder.finish();

    return Buffer.toArray(decoded_response.buffer);
  };

  public func store_image(name : Text, image : [Nat8]) : async () {
    let compressed = await* compress_data(image);
    map.put(name, compressed);
  };

  public func is_exact_image(name : Text, new_image : [Nat8]) : async Bool {
    let ?compressed = map.get(name) else return false;
    let stored_image = await* decode_data(compressed);

    return stored_image == new_image;
  };
};
